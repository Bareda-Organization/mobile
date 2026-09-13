import 'dart:async';
import 'dart:convert';

import 'package:stomp_dart_client/stomp_dart_client.dart';

import 'package:baraeda_core/storage/token_storage.dart';
import 'package:baraeda_core/websocket/websocket_envelope.dart';
import 'package:baraeda_core/websocket/ws_backoff_policy.dart';
import 'package:baraeda_core/websocket/ws_connection_state.dart';

/// `/ws/location` 하나에 STOMP 로 붙는 공용 클라이언트 — `API_SPEC §7`.
///
/// 완료 조건 4가지를 이 클래스 하나가 책임진다.
/// 1. CONNECT 프레임에 `Authorization: Bearer {token}` 을 실어 인증한다
///    (토큰이 없으면 그 헤더 자체를 안 실어 서버가 `401 UNAUTHORIZED` 로
///    거부하는 것을 그대로 노출한다 — §4 판단 근거 참고).
/// 2. 구독 거부(`FORBIDDEN`)를 [forbiddenSubscriptions] 스트림으로 알린다.
/// 3. 끊기면 [WsBackoffPolicy] 로 계산한 간격만큼 대기했다가 자동 재연결한다
///    (무한 즉시 재시도가 아니다 — 상한 도달 시 [WsConnectionState.gaveUp]).
/// 4. 수신한 프레임을 [WebSocketEnvelope] 로 파싱해 넘긴다(id 흡수 포함).
///
/// **토큰 만료 처리** — CONNECT 는 한 번만 인증하고 서버가 만료를 이유로
/// 세션을 능동적으로 끊지 않는다(브리프 §4 판단 근거 3). 이 클래스는
/// `ApiClient` 의 401→재발급 로직을 중복 구현하지 않는다 — 대신 매
/// (재)연결 시도마다 [TokenStorage.readAccessToken] 을 **새로 읽는다.**
/// `ApiClient` 가 REST 401 을 만나 토큰을 갱신해 두면, 다음 WS 재연결이
/// 그 새 토큰을 자동으로 집는다. 지금 열려 있는 WS 세션 자체를 갱신된
/// 토큰으로 바꿔 끼우는 수단은 STOMP 프로토콜에 없다 — 재연결이 유일한
/// 갱신 계기다.
///
/// **구독 정리** — [subscribe] 가 돌려주는 [StompUnsubscribe] 를 화면이
/// `dispose()` 시점에 반드시 호출해야 한다. 이 클래스는 화면 생명주기를
/// 모르므로 구독을 자동으로 추적·정리하지 않는다 — 강제로 추적하면
/// 화면 프레임워크(위젯 트리)에 대한 가정이 이 패키지에 스며든다.
class BaraedaWebSocketClient {
  BaraedaWebSocketClient({
    required String url,
    required TokenStorage tokenStorage,
    this.backoffPolicy = const WsBackoffPolicy(),
    void Function(String message)? onDebugMessage,
  }) : _url = url,
       _tokenStorage = tokenStorage,
       _onDebugMessage = onDebugMessage ?? ((_) {});

  final String _url;
  final TokenStorage _tokenStorage;
  final void Function(String message) _onDebugMessage;

  /// 재연결 대기 간격 정책 — 시험이 주입해 실제 시간을 기다리지 않고
  /// 검증할 수 있게 `final` 이 아니라 생성자 파라미터로 남겨 둔다.
  final WsBackoffPolicy backoffPolicy;

  StompClient? _stompClient;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _manuallyDisconnected = true;

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

  final _stateController = StreamController<WsConnectionState>.broadcast();
  WsConnectionState _state = WsConnectionState.disconnected;

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

  Stream<String> get forbiddenSubscriptions => _forbiddenController.stream;

  /// 연결을 시작한다. [WsConnectionState.gaveUp] 상태에서 다시 호출하면
  /// 시도 횟수가 0 으로 리셋되어 재시도가 재개된다 — 화면의 "다시 시도"
  /// 버튼이 이 메서드 하나만 부르면 된다.
  void connect() {
    _manuallyDisconnected = false;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    unawaited(_doConnect());
  }

  Future<void> _doConnect() async {
    _reconnectHandled = false;
    // 새 소켓은 이전 세션의 구독을 이어받지 않는다 — 화면이 `connected`
    // 를 다시 받으면 알아서 재구독하므로, 옛 목적지가 여기 남아 있으면
    // 다음 FORBIDDEN 이 엉뚱한(이미 끊긴) 목적지를 다시 흘려보낸다.
    _pendingSubscriptions.clear();
    _setState(WsConnectionState.connecting);
    // 매 (재)연결마다 새로 읽는다 — 토큰 만료 처리 판단 근거 참고.
    final token = await _tokenStorage.readAccessToken();

    final config = StompConfig(
      url: _url,
      // 라이브러리 내장 재연결(고정 지연·무한 재시도)을 끈다 — 우리가
      // WsBackoffPolicy 로 직접 스케줄한다.
      reconnectDelay: Duration.zero,
      // `stompConnectHeaders` 가 STOMP CONNECT 프레임의 네이티브 헤더로
      // 나간다 — 여기 실어야 `StompAuthChannelInterceptor` 의
      // `getFirstNativeHeader` 가 읽는다. `webSocketConnectHeaders` 는
      // 순수 WS 핸드셰이크 HTTP 헤더라 서버가 안 읽으므로 쓰지 않는다.
      stompConnectHeaders: token == null
          ? const {}
          : {'Authorization': 'Bearer $token'},
      onConnect: (frame) {
        _reconnectAttempt = 0;
        _setState(WsConnectionState.connected);
      },
      onStompError: (frame) {
        final message = frame.headers['message'];
        // `StompAuthChannelInterceptor` 의 SUBSCRIBE 거부 경로는 전부
        // `BusinessException(ErrorCode.FORBIDDEN)` 을 던진다 — 이 저장소
        // 안에서 구독 거부를 나타내는 값은 이 문자열 하나뿐이다.
        if (message == 'FORBIDDEN' && !_forbiddenController.isClosed) {
          // 프레임 자체에는 `destination` 헤더가 없다 — 위 필드 문서 참고.
          // 이번 연결에서 걸어 둔 미해제 구독 전부를 거부로 흘려보낸다.
          for (final destination in _pendingSubscriptions) {
            // `_setState` 의 `isClosed` 가드와 같은 사정 — dispose 이후
            // 지연 도착한 ERROR 프레임이 닫힌 컨트롤러에 add 되는 것을
            // 막는다.
            _forbiddenController.add(destination);
          }
          _pendingSubscriptions.clear();
        }
        _onDebugMessage('[BaraedaWebSocketClient] STOMP ERROR: '
            '${frame.headers} ${frame.body}');
      },
      onWebSocketError: (error) {
        _onDebugMessage('[BaraedaWebSocketClient] WebSocket error: $error');
        // 소켓이 아예 안 열린 실패(서버 다운)는 `onWebSocketDone` 이 안 온다
        // — 아래 `_reconnectHandled` 가드 참고. 여기서도 같은 처리를 태운다.
        _handleDisconnected();
      },
      onWebSocketDone: _handleDisconnected,
      onDebugMessage: _onDebugMessage,
    );

    _stompClient = StompClient(config: config)..activate();
  }

  /// 연결 끊김·연결 실패 공통 처리. `onWebSocketError` 와 `onWebSocketDone`
  /// 양쪽에서 불릴 수 있어(필드 [_reconnectHandled] 문서 참고) 이번 연결
  /// 시도당 한 번만 실행되도록 가드한다.
  void _handleDisconnected() {
    if (_reconnectHandled) return;
    _reconnectHandled = true;

    if (_manuallyDisconnected) {
      _setState(WsConnectionState.disconnected);
      return;
    }

    _reconnectAttempt += 1;
    if (backoffPolicy.shouldGiveUp(_reconnectAttempt)) {
      _setState(WsConnectionState.gaveUp);
      return;
    }

    _setState(WsConnectionState.reconnecting);
    final delay = backoffPolicy.delayFor(_reconnectAttempt);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => unawaited(_doConnect()));
  }

  /// 재연결을 멈추고 연결을 닫는다. 화면 종료·로그아웃 시 호출한다.
  void disconnect() {
    _manuallyDisconnected = true;
    _reconnectTimer?.cancel();
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
    final unsubscribe = client.subscribe(
      destination: destination,
      callback: (frame) {
        final body = frame.body;
        if (body == null) return;
        final envelope = WebSocketEnvelope.fromJson(
          jsonDecode(body) as Map<String, dynamic>,
        );
        onEnvelope(envelope);
      },
    );
    // 화면이 스스로 정상 해제했으면 이 목적지는 더 이상 "거부 여부를
    // 지켜봐야 할 미해제 구독"이 아니다 — 반환하는 unsubscribe 를 감싸
    // 해제 시점에 [_pendingSubscriptions] 에서도 함께 뺀다.
    return ({Map<String, String>? unsubscribeHeaders}) {
      _pendingSubscriptions.remove(destination);
      unsubscribe(unsubscribeHeaders: unsubscribeHeaders);
    };
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
  }
}
