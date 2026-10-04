import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/constants/api_constants.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/emergency/presentation/emergency_providers.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';
import 'package:meta/meta.dart';

/// DriveMode·StopRoster 가 그리는 실시간 연결 배지 상태 — `API_SPEC §7`
/// `/topic/manager/runs/{runId}` 구독의 화면 표현.
///
/// [WsConnectionState] 를 그대로 노출하지 않는 이유 — `disconnected` 는
/// "아직 연결을 시도한 적이 없다"(초기값)와 "수동으로 끊었다" 둘 다를
/// 뜻하는데, [ManagerRunChannelController] 는 생성 즉시 `connect()` 를
/// 부르므로 화면이 관측할 수 있는 초기 프레임은 사실상 없다 — 그 틈을
/// [connecting] 으로 메운다(빈 화면보다 "연결 중" 배지가 낫다는 판단,
/// 보고서 §1). [forbidden] 은 이 채널에만 있는 상태로, 서버가 4403 으로
/// 세션을 닫은 뒤에는 [WsConnectionState] 의 자동 재연결이 아예 의미가
/// 없어(배정되지 않은 회차를 계속 재시도해 봐야 다시 거부된다) 별도로
/// 분리한다.
enum ManagerChannelStatus {
  /// CONNECT 프레임 전송~응답 대기, 또는 아직 연결을 시작하지 않은 초기값.
  connecting,

  /// 구독 가능 — 화면은 배너를 감춘다.
  connected,

  /// 끊겨서 백오프 대기 중 — 자동으로 [connecting] 으로 돌아간다.
  reconnecting,

  /// 재시도 상한 도달 — 더 이상 자동 재연결하지 않는다. 기본 정책은 상한이 없어(R46-FIXRT S-5) 운영에서는
  /// 이 상태에 들지 않는다.
  gaveUp,

  /// 이 회차에 배정되지 않은 매니저가 구독을 시도해 서버가 4403 으로
  /// 세션을 닫았다(`ForbiddenSubscriptionCloseFactory`). [gaveUp] 과 달리
  /// 재시도 자체가 무의미하다 — 배정이 바뀌기 전까지 같은 결과가 나온다.
  forbidden,
}

/// [WsConnectionState] → [ManagerChannelStatus] 매핑. 나머지 로직과 분리한
/// 순수 함수라 WebSocket·Riverpod 없이 단위 시험이 가능하다.
ManagerChannelStatus mapConnectionState(WsConnectionState state) =>
    switch (state) {
      // 클래스 문서 참고 — 화면이 실제로 이 값을 받는 경우는 없다시피 하다
      // (컨트롤러가 생성 즉시 connect() 를 불러 바로 connecting 으로 넘어간다).
      // 그래도 배지 없음보다는 "연결 중"이 낫다고 판단해 connecting 에 합친다.
      WsConnectionState.disconnected => ManagerChannelStatus.connecting,
      WsConnectionState.connecting => ManagerChannelStatus.connecting,
      WsConnectionState.connected => ManagerChannelStatus.connected,
      WsConnectionState.reconnecting => ManagerChannelStatus.reconnecting,
      WsConnectionState.gaveUp => ManagerChannelStatus.gaveUp,
    };

/// `WsEventType` → 화면 무효화 대상 매핑. [WebSocketEnvelope] 전체가 아니라
/// [WsEventType] 만 받는다 — 이 채널이 다루는 6종 전부 "받으면 해당 목록을
/// 다시 조회한다"만 하고 payload 필드를 직접 쓰지 않기 때문이다(로스터·명단
/// 재조회가 서버 정본을 그대로 반영하므로 payload 를 화면 상태에 수동으로
/// 병합할 이유가 없다 — 병합 로직은 곧 또 하나의 정합성 버그 원인이 된다).
/// `position`·`emergency_raised`·`emergency_canceled`·
/// `approval_requested` 는 매니저 채널이
/// 방송하지 않는 이벤트라(`WsChannel.managerRun` 문서 참고) 무시한다.
void dispatchManagerChannelEvent(
  WsEventType? event, {
  required void Function() onRiderChanged,
  required void Function() onStopArrived,
  required void Function() onRunStarted,
  required void Function() onRunEnded,
  required void Function() onEmergencyAcked,
  required void Function() onRouteChanged,
}) {
  switch (event) {
    case WsEventType.riderChanged:
      onRiderChanged();
    case WsEventType.stopArrived:
      onStopArrived();
    case WsEventType.runStarted:
      onRunStarted();
    case WsEventType.runEnded:
      onRunEnded();
    case WsEventType.emergencyAcked:
      onEmergencyAcked();
    case WsEventType.routeChanged:
      onRouteChanged();
    case WsEventType.position:
    case WsEventType.emergencyRaised:
    case WsEventType.emergencyCanceled:
    case WsEventType.approvalRequested:
    case null:
      break;
  }
}

/// 앱이 백그라운드에서 돌아올 때마다 하나씩 오르는 신호(R46-FIXRT S-5) — 홈 화면의 복귀 훅이 올리고,
/// [ManagerRunChannelController] 가 보고 다음 재연결 타이머(최대 30초)를 기다리지 않고 바로 다시 붙는다.
/// 값 자체에는 뜻이 없다 — 바뀌었다는 사실이 신호다.
final StateProvider<int> appResumedProvider = StateProvider<int>((ref) => 0);

/// 서버에 다시 닿았다는 신호(R46-FIXCONN C-10) — 위치 전송(REST)이 성공할
/// 때마다 하나씩 오른다. 음영에서 나와 망이 돌아와도 실시간 연결은 재연결
/// 대기(최대 30초)가 끝나야 붙으므로, [ManagerRunChannelController] 가 이
/// 신호를 보고 바로 다시 붙는다. 이미 연결돼 있거나 연결 중이면
/// 클라이언트가 건드리지 않아([BaraedaWebSocketClient.reconnectNow]) 2초마다
/// 올라도 무해하다.
final StateProvider<int> serverReachedProvider = StateProvider<int>((ref) => 0);

/// 이벤트가 몰려도 명단·노선을 이 간격 안에서는 한 번만 다시 받는다(R46-FIXRT L4). 한 정류장에서 승차가
/// 몰리면 방송 한 건마다 같은 조회가 탭마다 연달아 나가므로, 첫 이벤트 뒤 이 시간을 기다렸다 한 번에 읽는다.
const Duration runViewRefetchWindow = Duration(seconds: 1);

/// `runId` 하나에 대한 `/topic/manager/runs/{runId}` 구독을 소유하는
/// 컨트롤러 — DriveMode·StopRoster 화면이 각자 [managerRunChannelProvider]
/// 로 이 컨트롤러를 얻는다(두 화면은 기사·동승자로 역할이 갈려 한 세션에
/// 동시에 뜨지 않는다 — `home_screen.dart` `_openRun` · 보고서 §1).
///
/// 생성자가 [BaraedaWebSocketClient.connectionState] ·
/// [BaraedaWebSocketClient.forbiddenSubscriptions] 를 구독한 **다음에**
/// `connect()` 를 부른다 — 순서를 바꾸면 `_doConnect()` 가 `await` 이전에
/// 동기로 내보내는 첫 `connecting` 이벤트를 영영 놓친다(broadcast 스트림은
/// 늦게 붙은 리스너에게 과거 이벤트를 다시 보내지 않는다).
class ManagerRunChannelController extends StateNotifier<ManagerChannelStatus> {
  /// [client] 는 시험 전용 주입점이다(`@visibleForTesting`) — 생략하면
  /// 운영과 같은 실제 [BaraedaWebSocketClient] 를 만든다. `??` 는 오른쪽을
  /// [client] 가 `null` 일 때만 평가하므로, 시험이 가짜를 넘기면
  /// `tokenStorageProvider`·`apiClientProvider` 를 굳이 override 하지
  /// 않아도 된다.
  new(
    this._ref,
    this._runId, {
    @visibleForTesting BaraedaWebSocketClient? client,
  }) : _client =
           client ??
           BaraedaWebSocketClient(
             url: wsUrlFromApiBaseUrl(ApiConstants.baseUrl),
             tokenStorage: _ref.read(tokenStorageProvider),
             // REST 401 재발급과 같은 창구를 쓴다 — 동시 재발급 경합을 막는
             // 이유는 `token_refresher.dart` 문서를 본다.
             refreshAccessToken: _ref
                 .read(apiClientProvider)
                 .tokenRefresher
                 .refresh,
           ),
       super(ManagerChannelStatus.connecting) {
    _connectionSub = _client.connectionState.listen(_onConnectionState);
    _forbiddenSub = _client.forbiddenSubscriptions.listen(_onForbidden);
    _sessionExpiredSub = _client.sessionExpired.listen(
      (_) => _onSessionExpired(),
    );
    _client.connect();
    // 앱 복귀 — 끊겨 대기 중인 연결을 바로 붙인다. 거부(forbidden)로 일부러 끊은 연결은 클라이언트가
    // 되살리지 않는다(`reconnectNow` 문서).
    _ref
      ..listen<int>(appResumedProvider, (_, _) => _client.reconnectNow())
      // 망 복귀 — 위치 전송이 서버에 닿으면 재연결 대기를 기다리지 않는다
      // (R46-FIXCONN C-10).
      ..listen<int>(serverReachedProvider, (_, _) => _client.reconnectNow());
  }

  final Ref _ref;
  final String _runId;
  final BaraedaWebSocketClient _client;
  late final StreamSubscription<WsConnectionState> _connectionSub;
  late final StreamSubscription<String> _forbiddenSub;
  late final StreamSubscription<void> _sessionExpiredSub;

  /// `subscribe()` 가 돌려준 해제 콜백 — 타입을 `StompUnsubscribe` 로 적으면
  /// `stomp_dart_client` 를 이 앱의 직접 의존성으로 새로 추가해야 한다
  /// (`baraeda_core` 만 그 패키지에 의존해도 되게 하려는 경계, 브리프 제약
  /// "baraeda_core 는 읽기만"과 같은 취지). 구조적 타입이 같아 이 함수
  /// 타입으로도 그대로 대입·호출된다.
  void Function({Map<String, String>? unsubscribeHeaders})? _unsubscribe;

  /// 서버가 4403 으로 세션을 이미 닫은 뒤에는 뒤늦게 도착하는
  /// `connectionState` 이벤트(재연결 로직이 다시 시도하며 내는 값)를
  /// 무시한다 — 이미 [ManagerChannelStatus.forbidden] 으로 확정됐다.
  bool _forbidden = false;

  /// 한 번이라도 연결된 적이 있는지 — 두 번째 이후 `connected` 는 끊겼다 돌아온 것이라, 그동안 놓친
  /// 방송을 되찾으려고 화면 값을 다시 받는다(F06-09).
  bool _wasConnected = false;

  /// 연결이 끊긴 채로 처음 확인된 시각 — 연결 끊김 띠의 `HH:mm 부터`. 재시도 중 `connecting` ↔
  /// `reconnecting` 을 오가도 처음 시각을 지키고, 다시 `connected` 가 되면 지운다. 처음 연결을 시도하는 중
  /// (`connecting`)은 끊긴 것이 아니라 세지 않는다.
  DateTime? get offlineSince => _offlineSince;
  DateTime? _offlineSince;

  void _onConnectionState(WsConnectionState wsState) {
    if (_forbidden) return;
    final mapped = mapConnectionState(wsState);
    if (mapped == ManagerChannelStatus.reconnecting) {
      _offlineSince ??= _ref.read(clockProvider).now();
    } else if (mapped == ManagerChannelStatus.connected) {
      _offlineSince = null;
    }
    state = mapped;
    if (wsState == WsConnectionState.connected) {
      if (_wasConnected) {
        _ref.invalidate(todayRunsProvider);
        _invalidateRunViews();
      }
      _wasConnected = true;
      // 새 소켓은 이전 세션의 구독을 이어받지 않는다
      // (`BaraedaWebSocketClient` 클래스 문서) — connected 를 받을 때마다,
      // 즉 최초 연결이든 자동 재연결이든 매번 다시 구독한다.
      _unsubscribe?.call();
      _unsubscribe = _client.subscribe(
        WsChannel.managerRun(_runId),
        _onEnvelope,
      );
    }
  }

  void _onForbidden(String destination) {
    _forbidden = true;
    state = ManagerChannelStatus.forbidden;
    // 재시도 자체가 무의미한 상태라 클라이언트를 완전히 멈춘다 — 그대로
    // 두면 백오프 정책에 따라 계속 재연결·재구독·재거부가 반복된다.
    _client.disconnect();
  }

  /// WS 재발급까지 실패해 세션을 되살릴 수 없다는 신호
  /// ([BaraedaWebSocketClient.sessionExpired]) — REST 401 재발급 실패가
  /// 이미 거치는 것과 같은 경로(`account_session.dart` 의
  /// `applyRoleAndStatus`)로 역할·상태를 비운다. 라우터가 그 변화를 보고
  /// 로그인 화면으로 보낸다(`router.dart` redirect, `signOut` 과 같은
  /// 판정 — 여기서는 화면 전환을 직접 하지 않는다). 재시도해 봐야 같은
  /// 토큰으로 다시 거부되므로 클라이언트도 멈춘다.
  void _onSessionExpired() {
    _client.disconnect();
    endSessionAsExpired(_ref);
  }

  void _onEnvelope(WebSocketEnvelope envelope) {
    // 이 소켓은 한 회차의 채널만 구독하지만, 다른 회차 봉투가 섞여 와도 이 화면의
    // 노선·명단을 다시 불러오지 않는다.
    if (envelope.runId != _runId) return;
    dispatchManagerChannelEvent(
      envelope.event,
      // 미승차 반영이 §4.3 실시간 노선의 정의 자체다("확정 노선 + 미승차
      // 반영") — RouteMapScreen 도 함께 무효화한다.
      onRiderChanged: _invalidateRunViews,
      // `current_stop`·`next_stop` 이 바뀌는 자리라 지도도 다시 그린다.
      onStopArrived: _invalidateRunViews,
      onRunStarted: () {
        // 회차 상태(idle/confirmed → moving)가 바뀌어 두 화면의 액션
        // 버튼·헤더가 함께 갱신돼야 한다 — `todayRunsProvider` 가 그 값의
        // 원본이다(`driveModeRunProvider`·`selectedManagerRunProvider` 참고).
        _ref.invalidate(todayRunsProvider);
        _invalidateRunViews();
      },
      onRunEnded: () {
        _ref.invalidate(todayRunsProvider);
        _invalidateRunViews();
      },
      onEmergencyAcked: () {
        _ref.invalidate(emergencyListProvider);
      },
      // 확정 뒤 노선(승하차지·도로 경로)이 바뀐 자리 — 지도·남은 승하차지를 새로 받는다.
      // `ack_required`(변경 확인 띠)는 회차 목록에서 오므로 그것도 다시 받는다(F06-08).
      onRouteChanged: () {
        _ref.invalidate(todayRunsProvider);
        _invalidateRunViews();
      },
    );
  }

  /// 이미 다시 읽기를 기다리는 중이면 새 이벤트는 그 묶음에 들어간다 — 타이머를 밀지 않는다. 이벤트가
  /// 쉬지 않고 이어져도 화면이 [runViewRefetchWindow] 보다 오래 낡지 않고, 조회는 그 간격에 한 번을 넘지 않는다.
  Timer? _refetchTimer;

  /// 운행 화면이 그리는 명단(§4.2·두 화면)과 노선(§4.3)을 버려 다시 조회하게 한다 —
  /// [runViewRefetchWindow] 뒤에 한 번.
  void _invalidateRunViews() {
    if (_refetchTimer?.isActive ?? false) return;
    _refetchTimer = Timer(runViewRefetchWindow, () {
      if (!mounted) return;
      _ref
        ..invalidate(rosterProvider)
        ..invalidate(driveModeRosterProvider)
        ..invalidate(routeProvider);
    });
  }

  @override
  void dispose() {
    _refetchTimer?.cancel();
    unawaited(_connectionSub.cancel());
    unawaited(_forbiddenSub.cancel());
    unawaited(_sessionExpiredSub.cancel());
    _unsubscribe?.call();
    _client.dispose();
    super.dispose();
  }
}

/// DriveMode·StopRoster 가 `ref.watch(managerRunChannelProvider(runId))` 로
/// 읽는 진입점. `autoDispose` 라 두 화면 다 언마운트되면(예: 홈으로 돌아가
/// 다른 회차를 고르면) 소켓도 함께 정리된다 — 앱 전역 싱글턴으로 두지
/// 않은 이유는 화면이 하나도 없을 때 배정 안 된 회차의 소켓을 계속 물고
/// 있을 이유가 없기 때문이다(보고서 §1 "화면별 인스턴스 vs 전역 싱글턴").
final StateNotifierProviderFamily<
  ManagerRunChannelController,
  ManagerChannelStatus,
  String
>
managerRunChannelProvider = StateNotifierProvider.autoDispose
    .family<ManagerRunChannelController, ManagerChannelStatus, String>(
      ManagerRunChannelController.new,
    );
