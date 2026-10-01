import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:baraeda_core/storage/token_storage.dart';
import 'package:baraeda_core/time/clock.dart';
import 'package:baraeda_core/websocket/token_renewal.dart';
import 'package:baraeda_core/websocket/websocket_envelope.dart';
import 'package:baraeda_core/websocket/ws_backoff_policy.dart';
import 'package:baraeda_core/websocket/ws_connection_state.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

/// [BaraedaWebSocketClient.subscribe] 로 걸어 둔 구독 한 건 — 만료 전 갈아타기가
/// 같은 구독을 새 연결에 다시 걸 수 있게 클라이언트가 직접 들고 있는다.
class _ActiveSubscription {
  _ActiveSubscription(this.id, this.destination, this.onEnvelope);

  final int id;
  final String destination;
  final void Function(WebSocketEnvelope envelope) onEnvelope;

  /// 이 구독이 걸려 있는 연결 → 그 연결의 해제 함수(갈아타는 동안만 둘이다).
  final Map<StompClient, StompUnsubscribe> handles = {};
}

/// 갈아타려고 새로 연 두 번째 연결 — 옛 연결이 계속 방송을 받는 동안 구독을 모두
/// 걸고, 확인 대기가 끝나면 옛 연결을 대신한다.
class _Standby {
  _Standby(this.attempt, this.client, this.token);

  final int attempt;
  final StompClient client;
  final String token;

  /// 처음엔 연결 시도 한도 감시, `CONNECTED` 를 받은 뒤엔 구독 확인 대기.
  Timer? timer;
}

/// `/ws/location` 하나에 STOMP 로 붙는 공용 클라이언트 — `API_SPEC §7`.
///
/// 완료 조건 4가지를 이 클래스 하나가 책임진다.
/// 1. CONNECT 프레임에 `Authorization: Bearer {token}` 을 실어 인증한다
///    (토큰이 없으면 그 헤더 자체를 안 실어 서버가 `401 UNAUTHORIZED` 로
///    거부하는 것을 그대로 노출한다 — §4 판단 근거 참고).
/// 2. 구독 거부(`FORBIDDEN`)를 [forbiddenSubscriptions] 스트림으로 알린다.
/// 3. 끊기면 [WsBackoffPolicy] 로 계산한 간격만큼 대기했다가 자동 재연결한다
///    (즉시 재시도가 아니라 30초 상한 백오프 — 기본 정책은 포기하지 않는다.
///    상한을 준 정책이 도달하면 [WsConnectionState.gaveUp]).
/// 4. 수신한 프레임을 [WebSocketEnvelope] 로 파싱해 넘긴다(id 흡수 포함).
///
/// **토큰 만료 처리** — 서버는 연결에 쓰인 access 토큰이 만료되면 다음
/// 방송 대신 STOMP `ERROR` 프레임(`message:TOKEN_EXPIRED`)을 보내고 세션을
/// 능동적으로 닫는다(`API_SPEC §7`). 이 클래스는 그 프레임을 받으면
/// [refreshAccessToken](주입받은 콜백 — 실제로는 `ApiClient.tokenRefresher`
/// 의 재발급 창구를 그대로 공유한다, 앱 생성 지점의 배선 참고)을 **먼저**
/// 불러 새 access 토큰을 받은 뒤에만 재연결한다 — `ApiClient` 의 401→재발급
/// 로직을 중복 구현하지 않고 창구만 공유하는 이유는 REST·WS 가 동시에
/// 재발급을 시도하면 서버의 refresh 토큰 1회용 회전과 부딪히기 때문이다
/// (`token_refresher.dart` 문서). 재발급 실패(퇴사·차단·refresh 만료)는
/// [WsConnectionState.gaveUp] 이 아니라 [sessionExpired] 스트림으로 넘긴다 — 같은 토큰으로
/// 재시도해 봐야 다시 거부되므로 "재시도 버튼"이 뜻을 잃는다. 이 재연결은
/// 네트워크 실패가 아니라 예정된 갱신이라 [WsBackoffPolicy] 의 재시도
/// 횟수를 소모하지 않는다.
///
/// **만료 전 갈아타기(R46-LATERRT C-14)** — 연결에 쓴 토큰의 만료
/// [TokenRenewalTiming.lead] 전에 재발급해 새 토큰으로 두 번째 연결을 열고, 걸려
/// 있는 구독을 모두 그 연결에 옮겨 건 뒤 거부 신호 없이 확인 대기가 지나면 옛
/// 연결을 닫는다. 연결 상태는 `connected` 그대로라 [connectionState] 에 아무것도
/// 흘리지 않는다. 재발급·새 연결이 실패하면 옛 연결을 그대로 두고, 만료 뒤
/// `TOKEN_EXPIRED` 경로가 받는다. 갈아타는 동안 두 연결이 같은 방송을 보내면
/// (구독 + 원문 본문)이 같은 것은 한 번만 전달한다.
///
/// **구독 정리** — [subscribe] 가 돌려주는 [StompUnsubscribe] 를 화면이
/// `dispose()` 시점에 반드시 호출해야 한다. 이 클래스는 화면 생명주기를
/// 모르므로 구독을 자동으로 추적·정리하지 않는다 — 강제로 추적하면
/// 화면 프레임워크(위젯 트리)에 대한 가정이 이 패키지에 스며든다.
class BaraedaWebSocketClient {
  /// `url` 은 `/ws/location` 주소, `tokenStorage` 는 CONNECT 인증 토큰의 출처다.
  BaraedaWebSocketClient({
    required this._url,
    required this._tokenStorage,
    this.backoffPolicy = const WsBackoffPolicy(),
    Future<String?> Function()? refreshAccessToken,
    void Function(String message)? onDebugMessage,
    this.connectTimeout = const Duration(seconds: 10),
    this.pingInterval = const Duration(seconds: 10),
    this.renewalTiming = const TokenRenewalTiming(),
    StompClient Function(StompConfig config)? stompClientFactory,
    Clock clock = const SystemClock(),
  }) : // 필드는 비공개, 파라미터는 공개 이름(`refreshAccessToken:`)을
       // 유지한다(`token_refresher.dart` 와 같은 이유).
       // ignore: prefer_initializing_formals
       _refreshAccessToken = refreshAccessToken,
       _onDebugMessage = onDebugMessage ?? ((_) {}),
       _stompClientFactory = stompClientFactory ?? _defaultStompClient,
       // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을 쓴다.
       // ignore: prefer_initializing_formals
       _clock = clock;

  static StompClient _defaultStompClient(StompConfig config) =>
      StompClient(config: config);

  final String _url;
  final TokenStorage _tokenStorage;

  /// `TOKEN_EXPIRED` 를 받았을 때 부를 재발급 콜백 — 클래스 문서 "토큰 만료
  /// 처리" 참고. 앱이 아직 배선하지 않았으면(`null`) 재발급을 시도하지 않고
  /// 곧바로 [sessionExpired] 로 넘긴다 — 재발급 없이 같은 토큰을 다시
  /// 실어 봐야 서버가 다시 거부한다.
  final Future<String?> Function()? _refreshAccessToken;
  final void Function(String message) _onDebugMessage;

  /// 연결 시도 한 번이 `CONNECTED` 를 받기까지의 한도 — 소켓 열기와 STOMP
  /// 핸드셰이크를 합쳐 이 시간을 넘기면 시도를 끊고 백오프 재연결로 이어간다
  /// (`API_SPEC §7` 연결 한도 표, R46-FIXCONN C-4). 인터넷 없는 Wi-Fi·서버
  /// 인바운드 실행기 포화에서 OS 한도(수십~백 수십 초)까지 `connecting` 에
  /// 머물던 것을 막는다.
  final Duration connectTimeout;

  /// WebSocket 계층의 핑 주기 — `dart:io` 가 이 주기로 핑을 보내고 퐁이 없으면
  /// 소켓을 닫는다. STOMP 하트비트(무송신 20~30초)와 별개로 반쯤 죽은 TCP 를
  /// 잡는다(R46-FIXCONN K-2).
  final Duration pingInterval;

  /// 만료 전 갈아타기의 시간 값 — [TokenRenewalTiming] 참고.
  final TokenRenewalTiming renewalTiming;

  final StompClient Function(StompConfig config) _stompClientFactory;
  final Clock _clock;

  /// 서버가 이만큼 아무것도(하트비트 포함) 안 보냈으면 연결이 죽은 것으로 본다 —
  /// 서버·클라이언트 하트비트 10초의 2배이고 `stomp_dart_client` 의 수신 점검
  /// 기준(`ttl × 2`)과 같다(`API_SPEC §7` 연결 한도 표, R46-FIXCONN C-11).
  static const serverSilenceLimit = Duration(seconds: 20);

  /// 마지막으로 서버에서 무언가(CONNECTED·하트비트·메시지) 받은 시각 —
  /// `stomp_dart_client` 가 받은 모든 데이터를 디버그 메시지(`<<<`)로 알리는 것을
  /// 이용해 기록한다. 라이브러리가 이 값을 공개하지 않는다.
  DateTime? _lastServerActivity;

  /// 연결 시도마다 오르는 번호표 — 옛 시도의 소켓이 늦게 보내는 닫힘·오류·
  /// 연결 신호가 새 시도를 끊김으로 오인하게 하지 않는다. 강제 재연결([reconnectNow])이
  /// 옛 소켓을 닫고 바로 새 소켓을 열 때 필요하다.
  int _attemptSeq = 0;

  /// 지금 방송을 받는 연결의 번호 — 갈아타려고 연 연결은 번호를 받아도 이 값이
  /// 되기 전까지 밀려난 시도처럼 취급되지 않고 [_standby] 로 따로 가려진다.
  int _currentAttempt = 0;

  /// 지금 걸려 있는 구독 전부 — 갈아타기가 같은 구독을 새 연결에 옮기는 데 쓴다.
  /// 새 연결(재연결)은 구독을 이어받지 않으므로 [_doConnect] 가 비운다(화면이
  /// `connected` 를 다시 받아 직접 구독한다).
  final Set<_ActiveSubscription> _subscriptions = {};
  int _subscriptionSeq = 0;
  Timer? _renewTimer;
  _Standby? _standby;

  /// 갈아타는 동안(과 그 직후) 본 방송 키 — 두 연결에서 같은 방송이 오면 한 번만
  /// 전달한다([_deliver]). `null` 이면 거르지 않는다.
  Set<String>? _seenDuringSwap;

  /// 재연결 대기 간격 정책 — 시험이 주입해 실제 시간을 기다리지 않고
  /// 검증할 수 있게 `final` 이 아니라 생성자 파라미터로 남겨 둔다.
  final WsBackoffPolicy backoffPolicy;

  final _random = Random();
  StompClient? _stompClient;
  Timer? _reconnectTimer;

  /// 연결 시도 시작 뒤 [connectTimeout] 안에 `CONNECTED` 가 오는지 지켜보는
  /// 감시 — `_doConnect` 가 걸고, 연결되거나 끊기면 푼다.
  Timer? _connectWatchdog;
  int _reconnectAttempt = 0;
  bool _manuallyDisconnected = true;

  /// [connect]·[disconnect] 가 불릴 때마다 오르는 세대 표식 — `await` 를 건너는 진행 중 작업
  /// (`_doConnect`·`_handleTokenExpired`)이 시작 때 읽어 둔 값과 다르면, 기다리는 사이 화면이
  /// 종료·로그아웃했거나 새로 연결한 것이므로 자기 몫의 소켓을 만들지 않고 물러난다.
  int _epoch = 0;

  /// 이번 연결 시도 한 번에 대해 재연결 스케줄을 이미 처리했는지 — 아래
  /// `_handleDisconnected` 의 이중 호출을 막는 가드. `stomp_dart_client` 는
  /// `reconnectDelay: Duration.zero` 일 때 **소켓 자체가 안 열리는 실패**
  /// (서버가 꺼져 있어 연결 자체가 거부됨)에서는 `onWebSocketDone` 을 부르지
  /// 않고 `onWebSocketError` 만 부른다(`stomp_handler.dart` `start()` 의
  /// catch 분기 — `reconnectDelay == 0` 이면 `_onDone()` 을 건너뛰고
  /// `_cleanUp()` 만 한다). 반대로 **연결된 뒤 끊어지는 실패**는
  /// `onWebSocketDone` 만 부른다. 둘 중 어느 쪽만 믿으면 나머지 경로에서
  /// 재연결 스케줄이 조용히 멈춘다 — 처음엔 `onWebSocketDone` 하나만 걸어
  /// 뒀다가, 서버가 꺼진 채로 재시도하는 시나리오에서 재연결이 두 번째
  /// 시도부터 멈추는 것을 이 필드를 추가하기 전에 실제로 확인했다.
  bool _reconnectHandled = false;

  /// 이번 연결이 끊긴 원인이 `TOKEN_EXPIRED` 였는지 — `onStompError` 가
  /// 세워 두면 뒤이어 오는 `onWebSocketDone`(`_handleDisconnected`)이 이
  /// 플래그를 보고 일반 백오프 대신 재발급 경로(`_handleTokenExpired`)를
  /// 탄다.
  bool _tokenExpired = false;

  final _stateController = StreamController<WsConnectionState>.broadcast();
  WsConnectionState _state = WsConnectionState.disconnected;

  /// 재발급까지 실패해 이 세션을 되살릴 수 없을 때 한 번 흘려보내는 신호 —
  /// 클래스 문서 "토큰 만료 처리" 참고. 화면은 이걸 받으면 로그인 화면으로
  /// 보내야 한다.
  final _sessionExpiredController = StreamController<void>.broadcast();

  /// 매 구독 거부(`FORBIDDEN`)마다 그 목적지 문자열을 흘려보낸다. 화면은
  /// 이걸 받으면 같은 목적지 재구독을 멈춰야 한다 — 이 클라이언트는 거부된
  /// 목적지를 스스로 기억해 재시도를 막지 않는다(전송 계층 클라이언트가
  /// 화면별 구독 정책까지 갖는 것은 책임 과다).
  final _forbiddenController = StreamController<String>.broadcast();

  /// 이번 연결에서 [subscribe] 로 걸어 뒀지만 아직 [StompUnsubscribe] 로
  /// 해제하지 않은 목적지들 — `onStompError` 가 어느 목적지가 거부됐는지
  /// 알아낼 유일한 단서다. 서버의 STOMP ERROR 프레임은 `destination`
  /// 헤더를 싣지 않는다(`onDebugMessage` 로 원시 프레임을 직접 찍어
  /// 확인 — `message:FORBIDDEN`·`content-length:0` 뿐이고 `destination` 은
  /// 없다). 여러 목적지를 동시에 구독한 상태에서 그중 하나만 거부돼도
  /// **전부**를 [forbiddenSubscriptions] 로 흘려보낸다 — 서버가 SUBSCRIBE
  /// 거부 즉시 세션 전체를 4403 으로 닫아(`ForbiddenSubscriptionCloseFactory`)
  /// 나머지 구독도 함께 무효가 되므로, 누락보다 과다 신고가 안전하다.
  final List<String> _pendingSubscriptions = [];

  /// 현재 연결 상태. 화면이 배지·재연결 안내를 그리는 데 쓴다.
  Stream<WsConnectionState> get connectionState => _stateController.stream;

  /// 최근 상태값 — 스트림 구독 전에 이미 지나간 상태를 놓치지 않기 위한
  /// 동기 조회.
  WsConnectionState get state => _state;

  /// 서버가 구독을 거부(`FORBIDDEN`)하면 그 구독의 destination 이 흘러온다.
  Stream<String> get forbiddenSubscriptions => _forbiddenController.stream;

  /// 재발급까지 실패해 세션을 되살릴 수 없을 때 흘러가는 신호 — 클래스
  /// 문서의 "토큰 만료 처리" 참고.
  Stream<void> get sessionExpired => _sessionExpiredController.stream;

  /// 연결을 시작한다. [WsConnectionState.gaveUp] 상태에서 다시 호출하면
  /// 시도 횟수가 0 으로 리셋되어 재시도가 재개된다 — 화면의 "다시 시도"
  /// 버튼이 이 메서드 하나만 부르면 된다.
  ///
  /// 이미 연결 중·연결됨이면 아무것도 하지 않는다(멱등) — 앱 전역 클라이언트 하나를 여러
  /// 화면이 저마다 불러도 소켓이 겹쳐 열리지 않는다.
  void connect() {
    _manuallyDisconnected = false;
    if (_state == WsConnectionState.connecting ||
        _state == WsConnectionState.connected) {
      return;
    }
    _epoch += 1;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    unawaited(_doConnect());
  }

  /// 앱이 백그라운드에서 돌아왔다 — 끊겨 재연결 대기 중([WsConnectionState.reconnecting])이거나 포기한
  /// ([WsConnectionState.gaveUp]) 연결을 다음 타이머(최대 30초)를 기다리지 않고 지금 다시 붙인다.
  /// 시도 횟수는 0 으로 돌아간다. 연결한 적 없거나(앱 복귀만으로 소켓을 새로 열지 않는다) 일부러 끊은
  /// (거부·로그아웃) 연결, 재발급 실패로 멈춘 세션([sessionExpired]), 연결 중인 연결은 모두
  /// `disconnected`·`connecting` 이라 건드리지 않는다.
  ///
  /// `connected` 인 연결은 마지막 서버 프레임(하트비트 포함)이
  /// [serverSilenceLimit] 을 넘었을 때만 죽은 것으로 보고 소켓을 닫고 새로
  /// 연다 — 백그라운드에서 소켓이 조용히 죽어도 상태는 `connected` 로 남아,
  /// 하트비트 점검(최대 10초 + 종료 시간)이 잡을 때까지 "연결됨" 으로
  /// 오인하던 것을 막는다(R46-FIXCONN C-11).
  void reconnectNow() {
    if (_state == WsConnectionState.connected) {
      if (_isServerSilent()) _restartConnection();
      return;
    }
    if (_state != WsConnectionState.reconnecting &&
        _state != WsConnectionState.gaveUp) {
      return;
    }
    connect();
  }

  bool _isServerSilent() {
    final last = _lastServerActivity;
    if (last == null) return false;
    return _clock.now().difference(last) > serverSilenceLimit;
  }

  /// 연결된 것으로 보이는 소켓을 닫고 새 소켓을 연다 — 시도 횟수는 0 으로 돌아간다.
  void _restartConnection() {
    _onDebugMessage(
      '[BaraedaWebSocketClient] 서버가 ${serverSilenceLimit.inSeconds}초 넘게 '
      '조용해 연결을 다시 연다',
    );
    _epoch += 1;
    _reconnectTimer?.cancel();
    _connectWatchdog?.cancel();
    try {
      _stompClient?.deactivate();
    } on StompBadStateException {
      // 소켓이 이미 죽어 DISCONNECT 를 쓰지 못했다 — 닫으려던 것이니
      // 무시한다([disconnect] 와 같은 사정).
    }
    _reconnectAttempt = 0;
    unawaited(_doConnect());
  }

  /// [overrideToken] 을 주면 저장소를 다시 읽지 않고 그 값을 그대로 싣는다
  /// — 재발급 직후([_handleTokenExpired])는 방금 받은 새 토큰이 손에 있는데
  /// 굳이 저장소 왕복을 한 번 더 거칠 이유가 없고, 콜백이 저장까지 했는지
  /// 여부에 기대지 않아도 된다(저장은 재발급 콜백의 책임이지 이 클래스가
  /// 강제할 계약이 아니다).
  Future<void> _doConnect({String? overrideToken}) async {
    final epoch = _epoch;
    final attempt = ++_attemptSeq;
    _currentAttempt = attempt;
    _cancelRenewal();
    _reconnectHandled = false;
    // 새 소켓은 이전 세션의 구독을 이어받지 않는다 — 화면이 `connected`
    // 를 다시 받으면 알아서 재구독하므로, 옛 목적지가 여기 남아 있으면
    // 다음 FORBIDDEN 이 엉뚱한(이미 끊긴) 목적지를 다시 흘려보낸다.
    _pendingSubscriptions.clear();
    _subscriptions.clear();
    _setState(WsConnectionState.connecting);
    // 매 (재)연결마다 새로 읽는다 — 토큰 만료 처리 판단 근거 참고.
    final token = overrideToken ?? await _tokenStorage.readAccessToken();
    // 토큰을 읽는 사이 disconnect()·새 connect() 가 있었으면 이 소켓은 만들지 않는다.
    if (epoch != _epoch) return;

    _stompClient = _stompClientFactory(_buildConfig(attempt, token))
      ..activate();
    _watchConnecting(epoch);
  }

  /// 연결 하나(첫 연결·재연결·갈아타려고 연 두 번째 연결)의 STOMP 설정. 번호표
  /// ([attempt])로 이 연결이 지금 누구 몫인지 가른다 — 지금 방송을 받는
  /// 연결이면 연결 상태 처리, 갈아타려고 연 연결이면 갈아타기 진행·실패 처리, 둘
  /// 다 아니면(밀려난 옛 연결) 무시한다.
  StompConfig _buildConfig(int attempt, String? token) {
    bool isStandby() => _standby?.attempt == attempt;
    return StompConfig(
      url: _url,
      // 라이브러리 내장 재연결(고정 지연·무한 재시도)을 끈다 — 우리가
      // WsBackoffPolicy 로 직접 스케줄한다.
      reconnectDelay: Duration.zero,
      // WebSocket 핑 — [pingInterval] 참고. 소켓 열기 한도는 라이브러리의
      // `connectionTimeout` 이 아니라 [_watchConnecting] 이 맡는다 — 소켓
      // 열기와 `CONNECTED` 를 한 번에 덮고, 클라이언트를 닫으면 같이 사라진다
      // (`connectionTimeout` 은 `Future.timeout` 타이머를 남겨 연결이 끝내 안
      // 되는 시험·종료 상황에서 타이머가 남는다).
      pingInterval: pingInterval,
      // `stompConnectHeaders` 가 STOMP CONNECT 프레임의 네이티브 헤더로
      // 나간다 — 여기 실어야 `StompAuthChannelInterceptor` 의
      // `getFirstNativeHeader` 가 읽는다. `webSocketConnectHeaders` 는
      // 순수 WS 핸드셰이크 HTTP 헤더라 서버가 안 읽으므로 쓰지 않는다.
      stompConnectHeaders: token == null
          ? const {}
          : {'Authorization': 'Bearer $token'},
      onConnect: (frame) {
        if (isStandby()) {
          _onStandbyConnected();
          return;
        }
        if (attempt != _currentAttempt) return;
        _connectWatchdog?.cancel();
        _lastServerActivity = _clock.now();
        _reconnectAttempt = 0;
        _setState(WsConnectionState.connected);
        if (token != null) _scheduleRenewal(token);
      },
      onStompError: (frame) {
        if (isStandby()) {
          _failStandby('STOMP ERROR ${frame.headers['message'] ?? ''}');
          return;
        }
        if (attempt != _currentAttempt) return;
        final message = frame.headers['message'];
        // API_SPEC §7 — 연결에 쓰인 access 토큰이 만료되면 서버가 이
        // 프레임으로 세션을 닫는다. 실제 재발급·재연결은 뒤이어 오는
        // `onWebSocketDone`(`_handleDisconnected`)이 이 플래그를 보고
        // 처리한다 — 여기서 바로 재발급을 시작하지 않는 이유는 서버가
        // 소켓을 닫는 시점과 순서를 맞추기 위해서다.
        if (message == 'TOKEN_EXPIRED') {
          _tokenExpired = true;
        }
        // `StompAuthChannelInterceptor` 의 SUBSCRIBE 거부 경로는 전부
        // `BusinessException(ErrorCode.FORBIDDEN)` 을 던진다 — 이 저장소
        // 안에서 구독 거부를 나타내는 값은 이 문자열 하나뿐이다.
        if (message == 'FORBIDDEN' && !_forbiddenController.isClosed) {
          // 프레임 자체에는 `destination` 헤더가 없다 — 위 필드 문서 참고.
          // 이번 연결에서 걸어 둔 미해제 구독 전부를 거부로 흘려보낸다.
          // `_setState` 의 `isClosed` 가드(위 조건)와 같은 사정 — dispose 이후
          // 지연 도착한 ERROR 프레임이 닫힌 컨트롤러에 add 되는 것을 막는다.
          _pendingSubscriptions
            ..forEach(_forbiddenController.add)
            ..clear();
        }
        _onDebugMessage(
          '[BaraedaWebSocketClient] STOMP ERROR: '
          '${frame.headers} ${frame.body}',
        );
      },
      onWebSocketError: (error) {
        _onDebugMessage('[BaraedaWebSocketClient] WebSocket error: $error');
        if (isStandby()) {
          _failStandby('WebSocket 오류');
          return;
        }
        if (attempt != _currentAttempt) return;
        // 소켓이 아예 안 열린 실패(서버 다운)는 `onWebSocketDone` 이 안 온다
        // — 아래 `_reconnectHandled` 가드 참고. 여기서도 같은 처리를 태운다.
        _handleDisconnected();
      },
      onWebSocketDone: () {
        if (isStandby()) {
          _failStandby('연결 닫힘');
          return;
        }
        if (attempt != _currentAttempt) return;
        _handleDisconnected();
      },
      onDebugMessage: (message) {
        if (attempt == _currentAttempt && message.startsWith('<<<')) {
          _lastServerActivity = _clock.now();
        }
        _onDebugMessage(message);
      },
    );
  }

  /// 소켓은 열렸는데 `CONNECTED` 가 안 오면(서버 인바운드 포화·반쯤 죽은 서버)
  /// 재연결 타이머는 close·error 뒤에만 예약되므로 `connecting` 에서 영영
  /// 막힌다. [connectTimeout] 안에 연결이 안 되면 이 시도를 끊고 끊김과 같은
  /// 경로로 백오프 재연결에 태운다(R46-FIXCONN C-4).
  void _watchConnecting(int epoch) {
    _connectWatchdog?.cancel();
    _connectWatchdog = Timer(connectTimeout, () {
      if (epoch != _epoch || _state != WsConnectionState.connecting) return;
      _onDebugMessage(
        '[BaraedaWebSocketClient] CONNECTED 를 ${connectTimeout.inSeconds}초 '
        '안에 못 받아 이 연결 시도를 끊는다',
      );
      try {
        _stompClient?.deactivate();
      } on StompBadStateException {
        // 소켓이 이미 닫힌 뒤라 DISCONNECT 를 쓰지 못했다 — 끊으려던 것이니
        // 무시한다([disconnect] 와 같은 사정).
      }
      _handleDisconnected();
    });
  }

  /// 연결 끊김·연결 실패 공통 처리. `onWebSocketError` 와 `onWebSocketDone`
  /// 양쪽에서 불릴 수 있어(필드 [_reconnectHandled] 문서 참고) 이번 연결
  /// 시도당 한 번만 실행되도록 가드한다.
  void _handleDisconnected() {
    _connectWatchdog?.cancel();
    if (_reconnectHandled) return;
    _reconnectHandled = true;
    _cancelRenewal();

    if (_manuallyDisconnected) {
      _setState(WsConnectionState.disconnected);
      return;
    }

    if (_tokenExpired) {
      _tokenExpired = false;
      unawaited(_handleTokenExpired());
      return;
    }

    _scheduleReconnect();
  }

  /// 백오프 정책대로 다음 재연결을 예약한다 — 정책에 상한이 있고 넘기면 [WsConnectionState.gaveUp].
  void _scheduleReconnect() {
    _reconnectAttempt += 1;
    if (backoffPolicy.shouldGiveUp(_reconnectAttempt)) {
      _setState(WsConnectionState.gaveUp);
      return;
    }

    _setState(WsConnectionState.reconnecting);
    final delay = backoffPolicy.jitteredDelayFor(_reconnectAttempt, _random);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => unawaited(_doConnect()));
  }

  /// `TOKEN_EXPIRED` 로 끊긴 뒤의 처리 — 클래스 문서 "토큰 만료 처리" 참고.
  /// 재발급에 성공하면 곧바로 재연결하고(백오프 횟수를 소모하지 않는다 —
  /// 예정된 갱신이지 네트워크 실패가 아니다), 실패하면(콜백이 없거나
  /// `null` 을 돌려주면) [sessionExpired] 로 넘기고 더 이상 재시도하지
  /// 않는다.
  Future<void> _handleTokenExpired() async {
    final epoch = _epoch;
    _setState(WsConnectionState.reconnecting);
    final refresh = _refreshAccessToken;
    final String? newToken;
    try {
      newToken = refresh == null ? null : await refresh();
    } on Object catch (error) {
      // 재발급 요청이 일시 장애로 실패했다(연결 실패·타임아웃·5xx) — 세션은 살아 있을 수
      // 있으므로 sessionExpired 로 넘기지 않고 일반 끊김처럼 백오프로 다시 시도한다.
      _onDebugMessage('[BaraedaWebSocketClient] 토큰 재발급 실패(일시): $error');
      if (epoch == _epoch) _scheduleReconnect();
      return;
    }
    // 재발급을 기다리는 사이 disconnect()(로그아웃)·새 connect() 가 있었다.
    if (epoch != _epoch) return;
    if (newToken == null) {
      if (!_sessionExpiredController.isClosed) {
        _sessionExpiredController.add(null);
      }
      _setState(WsConnectionState.disconnected);
      return;
    }
    _reconnectAttempt = 0;
    unawaited(_doConnect(overrideToken: newToken));
  }

  /// 재연결을 멈추고 연결을 닫는다. 화면 종료·로그아웃 시 호출한다.
  void disconnect() {
    _manuallyDisconnected = true;
    _epoch += 1;
    _reconnectTimer?.cancel();
    _connectWatchdog?.cancel();
    _cancelRenewal();
    try {
      _stompClient?.deactivate();
    } on StompBadStateException {
      // 서버가 SUBSCRIBE 거부(4403) 등으로 소켓을 이미 닫아 버린 뒤에
      // deactivate() 를 부르면, 내부적으로 DISCONNECT 프레임을 보내려다
      // 죽은 소켓에 쓰기를 시도해 이 예외가 난다(`stomp_handler.dart`
      // `_transmit`) — 실제로 완료 조건 2 시험의 tearDown 에서 확인했다.
      // 우리는 "이미 끊긴 연결을 끊어라" 라고 시켰을 뿐이니 무시한다.
    }
    _setState(WsConnectionState.disconnected);
  }

  /// [destination] 을 구독하고, 프레임마다 [WebSocketEnvelope] 로 파싱해
  /// [onEnvelope] 에 넘긴다. 반환값을 화면 `dispose()` 에서 호출해야 구독이
  /// 해제된다(클래스 문서의 "구독 정리" 참고).
  ///
  /// [WsConnectionState.connected] 가 아닐 때 호출하면 [StateError] —
  /// [connectionState] 스트림에서 `connected` 를 받은 뒤에 구독하라.
  StompUnsubscribe subscribe(
    String destination,
    void Function(WebSocketEnvelope envelope) onEnvelope,
  ) {
    final client = _stompClient;
    if (client == null || !client.connected) {
      throw StateError(
        '연결되지 않은 상태에서 subscribe($destination) 를 호출했다 — '
        'connectionState 스트림에서 WsConnectionState.connected 를 받은 '
        '뒤에 구독하라.',
      );
    }
    _pendingSubscriptions.add(destination);
    final entry = _ActiveSubscription(
      ++_subscriptionSeq,
      destination,
      onEnvelope,
    );
    _subscriptions.add(entry);
    _attachSubscription(client, entry);
    // 갈아타는 중이고 새 연결이 이미 열렸으면 새 연결에도 건다 — 안 그러면 옛
    // 연결을 닫는 순간 이 구독이 사라진다.
    final standbyClient = _standby?.client;
    if (standbyClient != null && standbyClient.connected) {
      _attachSubscription(standbyClient, entry);
    }
    // 화면이 스스로 정상 해제했으면 이 목적지는 더 이상 "거부 여부를
    // 지켜봐야 할 미해제 구독"이 아니다 — 반환하는 unsubscribe 를 감싸
    // 해제 시점에 [_pendingSubscriptions] 에서도 함께 뺀다.
    return ({Map<String, String>? unsubscribeHeaders}) {
      _subscriptions.remove(entry);
      _pendingSubscriptions.remove(destination);
      for (final unsubscribe in entry.handles.values.toList()) {
        try {
          unsubscribe(unsubscribeHeaders: unsubscribeHeaders);
        } on StompBadStateException {
          // 갈아타는 동안 둘 중 한 연결이 이미 닫혔다 — 그 연결의 구독은 서버에서도
          // 사라졌으니 풀 것이 없고, 다른 연결의 구독은 계속 풀어야 한다.
        }
      }
      entry.handles.clear();
    };
  }

  /// [client] 에 구독을 걸고 해제 함수를 구독 기록에 남긴다. 밀려난 연결(갈아타고
  /// 닫힌 옛 연결)이 늦게 보내는 프레임은 버린다.
  void _attachSubscription(StompClient client, _ActiveSubscription entry) {
    entry.handles[client] = client.subscribe(
      destination: entry.destination,
      callback: (frame) {
        if (!identical(client, _stompClient) &&
            !identical(client, _standby?.client)) {
          return;
        }
        final body = frame.body;
        if (body == null) return;
        _deliver(entry, body);
      },
    );
  }

  /// 갈아타는 동안 같은 방송이 두 연결에서 오면 한 번만 넘긴다. 방송 본문에 고유
  /// 식별자가 없고 STOMP `message-id` 는 세션마다 따로 붙으므로(`Ruling 682`)
  /// (구독 + 원문 본문)으로 가린다 — 서버는 같은 방송을 같은 바이트로 모든
  /// 구독자에게 보낸다.
  void _deliver(_ActiveSubscription entry, String body) {
    final seen = _seenDuringSwap;
    if (seen != null && !seen.add('${entry.id}\n$body')) return;
    final WebSocketEnvelope envelope;
    try {
      envelope = WebSocketEnvelope.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );
    } on Object catch (error) {
      // 서버 프레임 하나가 깨졌다고 STOMP 콜백 밖으로 예외를 흘리지 않는다 — 그 프레임만
      // 버리고 원인을 남겨 "이벤트가 안 온다" 로만 보이지 않게 한다.
      _onDebugMessage('[BaraedaWebSocketClient] 프레임 파싱 실패: $error');
      return;
    }
    entry.onEnvelope(envelope);
  }

  /// 접근 토큰 만료 [TokenRenewalTiming.lead] 전에 갈아타기를 예약한다. 만료
  /// 시각을 못 읽는 토큰이면 예약하지 않는다 — 그때는 기존 `TOKEN_EXPIRED` 경로가
  /// 받는다. 갈아탄 뒤에는 새 토큰의 만료 시각으로 다시 예약한다.
  void _scheduleRenewal(String token) {
    _renewTimer?.cancel();
    final expiresAt = readJwtExpiry(token);
    if (expiresAt == null) return;
    var delay = expiresAt.difference(_clock.now()) - renewalTiming.lead;
    if (delay < renewalTiming.minDelay) delay = renewalTiming.minDelay;
    _renewTimer = Timer(delay, () => unawaited(_renewConnection()));
  }

  /// 재발급 → 새 토큰으로 두 번째 연결. 재발급이 실패하면(콜백이 없거나 `null`·
  /// 예외) 아무것도 바꾸지 않는다 — 연결은 그대로 두고, 만료 뒤 서버가 보내는
  /// `TOKEN_EXPIRED` 가 기존 재발급·재연결 경로를 태운다(방송 공백은 이 기능이
  /// 없을 때와 같다).
  Future<void> _renewConnection() async {
    _renewTimer = null;
    final attempt = _currentAttempt;
    final refresh = _refreshAccessToken;
    if (refresh == null ||
        _manuallyDisconnected ||
        _state != WsConnectionState.connected) {
      return;
    }
    final String? newToken;
    try {
      newToken = await refresh();
    } on Object catch (error) {
      _onDebugMessage(
        '[BaraedaWebSocketClient] 만료 전 재발급 실패 — 기존 연결을 유지한다: $error',
      );
      return;
    }
    // 재발급을 기다리는 사이 연결이 끊겼거나 바뀌었으면(끊김·종료·재연결)
    // 갈아타지 않는다.
    if (newToken == null ||
        _manuallyDisconnected ||
        attempt != _currentAttempt ||
        _state != WsConnectionState.connected) {
      return;
    }
    _openStandby(newToken);
  }

  void _openStandby(String token) {
    final attempt = ++_attemptSeq;
    final client = _stompClientFactory(_buildConfig(attempt, token))
      ..activate();
    // 연결 시도 한도 — 소켓은 열렸는데 `CONNECTED` 가 안 오는 시도가 옛 연결을
    // 닫을 때까지(최대 [TokenRenewalTiming.lead]) 매달리지 않게 한다.
    _standby = _Standby(attempt, client, token)
      ..timer = Timer(connectTimeout, () => _failStandby('연결 시간 초과'));
  }

  /// 두 번째 연결이 `CONNECTED` 를 받았다 — 걸려 있는 구독을 모두 새 연결에 걸고,
  /// 확인 대기가 끝나면 옛 연결을 닫는다.
  void _onStandbyConnected() {
    final standby = _standby;
    if (standby == null) return;
    standby.timer?.cancel();
    _seenDuringSwap = {};
    for (final entry in _subscriptions) {
      _attachSubscription(standby.client, entry);
    }
    standby.timer = Timer(renewalTiming.subscribeSettle, _promoteStandby);
  }

  /// 확인 대기 동안 거부 신호가 없었다 — 새 연결이 방송 받는 연결이 되고 옛
  /// 연결을 닫는다. 연결 상태는 `connected` 그대로라 알림도 보내지 않는다.
  void _promoteStandby() {
    final standby = _standby;
    final previous = _stompClient;
    if (standby == null || previous == null) return;
    _standby = null;
    _stompClient = standby.client;
    _currentAttempt = standby.attempt;
    _lastServerActivity = _clock.now();
    for (final entry in _subscriptions) {
      entry.handles.remove(previous);
    }
    try {
      previous.deactivate();
    } on StompBadStateException {
      // 옛 연결이 이미 닫혀 있었다 — 닫으려던 것이니 무시한다([disconnect] 와
      // 같은 사정).
    }
    final seen = _seenDuringSwap;
    Timer(renewalTiming.dedupTail, () {
      if (identical(_seenDuringSwap, seen)) _seenDuringSwap = null;
    });
    _scheduleRenewal(standby.token);
  }

  void _failStandby(String reason) {
    if (_standby == null) return;
    _onDebugMessage(
      '[BaraedaWebSocketClient] 만료 전 갈아타기 실패($reason) — 기존 연결을 유지한다',
    );
    _abortStandby();
  }

  /// 갈아타기를 접고 두 번째 연결만 닫는다 — 옛 연결은 건드리지 않는다.
  void _abortStandby() {
    final standby = _standby;
    if (standby == null) return;
    _standby = null;
    _seenDuringSwap = null;
    standby.timer?.cancel();
    for (final entry in _subscriptions) {
      entry.handles.remove(standby.client);
    }
    try {
      standby.client.deactivate();
    } on StompBadStateException {
      // 이미 닫힌 연결을 다시 닫으려는 경우 — 무시한다.
    }
  }

  /// 예약된 갈아타기와 진행 중인 갈아타기를 모두 접는다 — 연결이 끊기거나 새로
  /// 시작되거나 닫힐 때.
  void _cancelRenewal() {
    _renewTimer?.cancel();
    _renewTimer = null;
    _abortStandby();
  }

  void _setState(WsConnectionState next) {
    _state = next;
    // `dispose()` 가 컨트롤러를 닫은 뒤에도 `stomp_dart_client` 의
    // `deactivate()` 가 비동기로 지연시킨 onWebSocketDone/onWebSocketError
    // 콜백이 뒤늦게 도착해 여기로 들어올 수 있다 — 그때 `add` 를 그대로
    // 부르면 `Bad state: Cannot add new events after calling close` 로
    // 터진다. 이미 닫힌 뒤라면 조용히 무시한다(더 이상 아무도 듣지 않는다).
    if (_stateController.isClosed) return;
    _stateController.add(next);
  }

  /// 스트림 컨트롤러를 닫는다 — [disconnect] 와 별개로, 이 클라이언트
  /// 자체를 더 쓰지 않을 때(앱 종료 등) 한 번만 호출한다.
  void dispose() {
    disconnect();
    unawaited(_stateController.close());
    unawaited(_forbiddenController.close());
    unawaited(_sessionExpiredController.close());
  }
}
