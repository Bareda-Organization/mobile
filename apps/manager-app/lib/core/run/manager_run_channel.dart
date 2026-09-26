import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
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

  /// 재시도 상한 도달 — 더 이상 자동 재연결하지 않는다.
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

/// REST `baseUrl`(`.../api/v1`)에서 STOMP 엔드포인트 URL 을 유도한다 —
/// `baraeda_core` 자체의 `test/integration/baraeda_websocket_client_connect_test.dart`
/// 가 쓰는 것과 같은 조립 방식이다(스킴 교체 + 경로를 `/ws/location` 으로
/// 고정). 그 시험은 항상 `http://localhost:...` 만 다뤄 무조건 `ws` 로
/// 바꾸지만, 이 함수는 배포 환경의 `https` 도 받을 수 있어야 하므로
/// `https` → `wss` 분기를 추가했다(그 테스트에는 없는 판단 — 보고서 §2).
String wsUrlFromApiBaseUrl(String apiBaseUrl) {
  final uri = Uri.parse(apiBaseUrl);
  final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
  // 쿼리·프래그먼트는 REST baseUrl 쪽 값이라 STOMP 엔드포인트에는 의미가
  // 없어 아예 뺀다 — `Uri.replace(query: '')` 는 "빈 쿼리가 있다" 로 남아
  // `?` 를 그대로 찍으므로 (`Uri.replace` 는 인자를 안 주면 원본 값을
  // 물려주고, 지우려면 새로 만드는 수밖에 없다) `Uri()` 로 새로 만든다.
  return Uri(
    scheme: wsScheme,
    userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: '/ws/location',
  ).toString();
}

/// `WsEventType` → 화면 무효화 대상 매핑. [WebSocketEnvelope] 전체가 아니라
/// [WsEventType] 만 받는다 — 이 채널이 다루는 5종 전부 "받으면 해당 목록을
/// 다시 조회한다"만 하고 payload 필드를 직접 쓰지 않기 때문이다(로스터·명단
/// 재조회가 서버 정본을 그대로 반영하므로 payload 를 화면 상태에 수동으로
/// 병합할 이유가 없다 — 병합 로직은 곧 또 하나의 정합성 버그 원인이 된다).
/// `position`·`emergency_raised`·`approval_requested` 는 매니저 채널이
/// 방송하지 않는 이벤트라(`WsChannel.managerRun` 문서 참고) 무시한다.
void dispatchManagerChannelEvent(
  WsEventType? event, {
  required void Function() onRiderChanged,
  required void Function() onStopArrived,
  required void Function() onRunStarted,
  required void Function() onRunEnded,
  required void Function() onEmergencyAcked,
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
    case WsEventType.position:
    case WsEventType.emergencyRaised:
    case WsEventType.approvalRequested:
    case null:
      break;
  }
}

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
  ManagerRunChannelController(
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
             refreshAccessToken:
                 _ref.read(apiClientProvider).tokenRefresher.refresh,
           ),
       super(ManagerChannelStatus.connecting) {
    _connectionSub = _client.connectionState.listen(_onConnectionState);
    _forbiddenSub = _client.forbiddenSubscriptions.listen(_onForbidden);
    _sessionExpiredSub = _client.sessionExpired.listen(
      (_) => _onSessionExpired(),
    );
    _client.connect();
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

  void _onConnectionState(WsConnectionState wsState) {
    if (_forbidden) return;
    state = mapConnectionState(wsState);
    if (wsState == WsConnectionState.connected) {
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
    applyRoleAndStatus(
      _ref.read(unsupportedRoleProvider.notifier),
      _ref.read(currentUserRoleProvider.notifier),
      _ref.read(currentAccountStatusProvider.notifier),
      role: null,
      status: null,
    );
  }

  void _onEnvelope(WebSocketEnvelope envelope) {
    dispatchManagerChannelEvent(
      envelope.event,
      onRiderChanged: () {
        // 미승차 반영이 §4.3 실시간 노선의 정의 자체다("확정 노선 + 미승차
        // 반영") — RouteMapScreen 도 함께 무효화한다.
        _ref
          ..invalidate(rosterProvider)
          ..invalidate(driveModeRosterProvider)
          ..invalidate(routeProvider);
      },
      onStopArrived: () {
        // `current_stop`·`next_stop` 이 바뀌는 자리라 지도도 다시 그린다.
        _ref
          ..invalidate(rosterProvider)
          ..invalidate(driveModeRosterProvider)
          ..invalidate(routeProvider);
      },
      onRunStarted: () {
        // 회차 상태(idle/confirmed → moving)가 바뀌어 두 화면의 액션
        // 버튼·헤더가 함께 갱신돼야 한다 — `todayRunsProvider` 가 그 값의
        // 원본이다(`driveModeRunProvider`·`selectedManagerRunProvider` 참고).
        _ref
          ..invalidate(todayRunsProvider)
          ..invalidate(rosterProvider)
          ..invalidate(driveModeRosterProvider)
          ..invalidate(routeProvider);
      },
      onRunEnded: () {
        _ref
          ..invalidate(todayRunsProvider)
          ..invalidate(rosterProvider)
          ..invalidate(driveModeRosterProvider)
          ..invalidate(routeProvider);
      },
      onEmergencyAcked: () {
        _ref.invalidate(emergencyListProvider);
      },
    );
  }

  @override
  void dispose() {
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
