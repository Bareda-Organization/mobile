import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/runs/presentation/run_providers.dart';
import 'package:parent_app/features/live_map/domain/live_map_status.dart';

/// `studentId` 별 실시간 위치 화면 상태 — `/topic/students/{studentId}/run`
/// 하나만 구독한다(공용 `webSocketClientProvider`, §1 판단 근거: 학부모는
/// `selectedStudentIdProvider` 로, 학생은 `myStudentIdProvider`
/// (`features/home`)로 각각 정확히 하나의 `studentId` 만 얻는다 — 두
/// 갈래 다 여러 목적지를 동시에 구독할 일이 설계상 없어 COMMON.md 의
/// 과다신고 조항이 걸리지 않는다). 이 provider 의 인자 타입이 `String`
/// (nullable 아님)이라, `selectedStudentIdProvider` 가 아직 `null` 인
/// 동안에는 이 notifier 자체가 만들어지지 않는다 — `live_map_screen.dart`
/// 의 두 화면 모두 `studentId` 를 확정한 뒤에만 `_LiveMapBody` 를 만든다.
///
/// `autoDispose.family` — 화면을 벗어나거나 자녀를 전환하면 이전
/// `studentId` 의 인스턴스가 해제되며 구독도 함께 해지된다. **실측
/// (`live_map_screen_test.dart` "자녀를 전환하면..." — 팀 리드 우려 3)**
/// 위젯 빌드가 새 `studentId` 로 다시 `ref.watch` 하는 시점에 새
/// 인스턴스의 구독이 먼저 걸리고, 더는 아무도 읽지 않는 이전 인스턴스는
/// 그 뒤 `dispose()` 로 해지된다 — 겹치지 않는다는 가정은 틀렸고, 실제로
/// 같은 프레임 안에서 두 목적지가 잠깐 겹친다. 이 겹침은 서버 쪽에서
/// 문제가 되지 않는다 — 두 목적지 모두 같은 학부모 **본인** 자녀 목적지라
/// FORBIDDEN 판정 대상이 아니다. 위험한 조합(남의 자녀 목적지가 섞이는
/// 것)은 애초에 `selectedStudentIdProvider` 값이 그 학부모의
/// `myStudentsProvider` 목록에서만 나오므로 이 provider 앞단에서 이미
/// 막힌다.
///
/// **거부(forbidden) 이후 복구 — 팀 리드 우려 4.** `BaraedaWebSocketClient`
/// 는 서버가 SUBSCRIBE 를 거부하면 세션 전체를 `4403` 으로 닫고, 그 뒤
/// `_manuallyDisconnected` 가 `false` 라 자동으로 재연결을 시도한다(다른
/// 화면의 실시간 기능이 계속 쓰는 공용 연결이라 이 자동 재연결 자체는
/// 유지해야 한다). 문제는 재연결이 성공하면 이 notifier 가 다시
/// `connected` 이벤트를 받는다는 것 — 아무 조치 없이 그 이벤트로
/// 재구독을 걸면 같은 거부 목적지를 다시 SUBSCRIBE 해 서버가 세션을 또
/// 닫는 반복(거부→종료→재연결→거부)이 생긴다. 그래서 `_onForbidden` 이
/// `_forbidden` 플래그를 세운 뒤로는 이 인스턴스가 연결 상태 이벤트를
/// 완전히 무시한다 — 화면은 "조회 권한 없음" 배너를 계속 보여주고,
/// 사용자가 다른 자녀로 전환하거나 화면을 벗어났다 돌아와야만(=
/// `autoDispose` 로 새 인스턴스가 생겨야만) 다시 시도한다. 같은 연결을
/// 쓰는 다른 `studentId` 인스턴스는 각자의 `_forbidden` 이 그대로
/// `false` 라 정상적으로 재구독한다.
// `StateNotifierProviderFamily<...>` 는 `flutter_riverpod` 가 공개 API 로
// export 하지 않는 내부 타입이라 명시할 수 없다 — `run_providers.dart` 의
// `runsForStudentProvider` 와 같은 사정.
// ignore: specify_nonobvious_property_types
final liveMapStateProvider = StateNotifierProvider.autoDispose
    .family<LiveMapNotifier, LiveMapState, String>(LiveMapNotifier.new);

class LiveMapNotifier extends StateNotifier<LiveMapState> {
  LiveMapNotifier(this._ref, this._studentId) : super(const LiveMapState()) {
    _init();
  }

  final Ref _ref;
  final String _studentId;

  /// [BaraedaWebSocketClient.subscribe] 가 돌려주는 해지 콜백 — 타입을
  /// 직접 이름 붙이지 않는다. `stomp_dart_client` 의 `StompUnsubscribe`
  /// 를 `baraeda_core` 배럴이 재노출하지 않아, 함수 타입 그대로 추론에
  /// 맡긴다.
  void Function({Map<String, String>? unsubscribeHeaders})? _unsubscribe;
  StreamSubscription<WsConnectionState>? _connectionSub;
  StreamSubscription<String>? _forbiddenSub;

  /// 이 `studentId` 목적지가 이미 거부당한 적이 있다 — 클래스 문서
  /// "거부 이후 복구" 참고. 한 번 서면 이 인스턴스는 다시 내려가지
  /// 않는다(새 인스턴스만 재시도한다).
  bool _forbidden = false;

  /// 마지막으로 이벤트를 받은 회차 — 다른 회차의 이벤트가 오면 앞 회차 표시를 비운다(F05-05).
  String? _runId;

  BaraedaWebSocketClient get _client => _ref.read(webSocketClientProvider);

  void _init() {
    // 이 지도가 살아 있는 동안 연결을 붙잡는다 — 마지막 지도가 닫히면 연결도 끊긴다(R46-FIXCONN C-2).
    _ref.listen(webSocketHoldProvider, (_, _) {});
    final client = _client;
    _applyConnectionState(client.state);
    _connectionSub = client.connectionState.listen(_onConnectionState);
    _forbiddenSub = client.forbiddenSubscriptions.listen(_onForbidden);

    if (client.state == WsConnectionState.connected) {
      _subscribe(client);
    } else {
      // `connect()` 는 `gaveUp` 상태에서 불러도 시도 횟수를 리셋해 재개한다
      // — 이미 연결·연결 시도 중이면 조용히 무시되므로 매번 불러도 안전
      // 하다(BaraedaWebSocketClient.connect 문서 참고).
      client.connect();
    }

    // API_SPEC §3.11 — WS 구독과 별개로, 첫 진입 시 한 번 REST 스냅샷을
    // 받는다("REST 스냅샷 → WS 갱신" 순서). WS 연결·구독을 막지 않도록
    // await 하지 않는다 — 실패해도 이 notifier 자체는 살아 있어야 한다.
    unawaited(_loadRestSnapshot());
  }

  /// §3.11 스냅샷 + 당일 결석 대조. `AsyncValue.guard` 로 감싸 예외 종류를
  /// 가리지 않고 전부 `restPosition` 에 담는다(`avoid_catches_without_on_clauses`
  /// 를 맨손 `catch` 없이 지키는 방법이기도 하다). 결석 대조
  /// (`runsForStudentProvider`)가 실패해도 스냅샷 자체는 그대로 반영한다
  /// — 결석 여부를 모를 뿐 좌표 스냅샷은 유효한 정보이기 때문이다.
  Future<void> _loadRestSnapshot() async {
    state = state.copyWith(restPosition: const AsyncValue.loading());

    final result = await AsyncValue.guard(
      () => _ref.read(busPositionRepositoryProvider).getBusPosition(_studentId),
    );
    if (!mounted) return;

    var isAbsent = false;
    final position = result.value;
    if (position != null) {
      final runsResult = await AsyncValue.guard(
        () => _ref.read(runsForStudentProvider(_studentId).future),
      );
      final runs = runsResult.value;
      if (runs != null) {
        isAbsent = runs.any(
          (run) =>
              run.runId == position.runId &&
              run.riderStatus == RiderStatus.absent,
        );
      }
    }

    if (!mounted) return;
    state = state.copyWith(restPosition: result, isAbsent: isAbsent);
  }

  void _onConnectionState(WsConnectionState wsState) {
    // 이미 거부당한 목적지다 — 연결이 되살아나도 반응하지 않는다
    // (클래스 문서 "거부 이후 복구"). 여기서 return 하지 않으면
    // `_applyConnectionState` 가 `state.connection` 을 `connected` 로
    // 덮어써 "조회 권한 없음" 배너가 사라지고, 그다음 조건이 같은
    // 거부 목적지로 재구독을 걸어 거부→세션 종료→재연결 반복이 생긴다.
    if (_forbidden) return;

    _applyConnectionState(wsState);
    if (wsState != WsConnectionState.connected) {
      // F05-04 — 소켓이 내려가면 그 위의 구독도 사라진다(새 소켓은 이어받지 않는다).
      // 해지 콜백을 비워 두어야 `connected` 로 돌아왔을 때 다시 구독한다.
      _unsubscribe = null;
    } else if (_unsubscribe == null) {
      _subscribe(_client);
      // 끊긴 사이 놓친 위치를 REST 스냅샷으로 메운다.
      unawaited(_loadRestSnapshot());
    }
  }

  /// 첫 연결 시도가 끝났다(연결됐거나 끊겨 재시도 대기에 들어갔다) — 이 뒤의
  /// `connecting` 은 첫 진입이 아니라 재시도라 스피너로 그리지 않는다(C-5).
  bool _firstAttemptSettled = false;

  void _applyConnectionState(WsConnectionState wsState) {
    // 재연결 시도마다 `connecting` 이 오므로, 그대로 매핑하면 끊김 중에 지도와
    // 전체 스피너가 시도 간격마다 번갈아 보인다. 스피너는 첫 진입의 첫 연결
    // 시도에만 쓰고 그 뒤의 재시도는 `reconnecting`(지도 + 안내 배너)로 둔다.
    if (wsState == WsConnectionState.connected ||
        wsState == WsConnectionState.reconnecting ||
        wsState == WsConnectionState.gaveUp) {
      _firstAttemptSettled = true;
    }
    final connection = switch (wsState) {
      WsConnectionState.disconnected => LiveMapConnection.idle,
      WsConnectionState.connecting =>
        _firstAttemptSettled
            ? LiveMapConnection.reconnecting
            : LiveMapConnection.connecting,
      WsConnectionState.connected => LiveMapConnection.connected,
      WsConnectionState.reconnecting => LiveMapConnection.reconnecting,
      WsConnectionState.gaveUp => LiveMapConnection.gaveUp,
    };
    state = state.copyWith(connection: connection);
  }

  void _subscribe(BaraedaWebSocketClient client) {
    _unsubscribe = client.subscribe(
      WsChannel.studentRun(_studentId),
      _onEnvelope,
    );
  }

  /// 이 화면이 구독한 목적지가 거부됐을 때만 반응한다 — 다른 화면(다른
  /// `studentId` 인스턴스)의 거부까지 여기서 받을 수 있어(§1 클라이언트
  /// 문서의 과다신고 조항) 목적지 문자열로 걸러야 한다.
  void _onForbidden(String destination) {
    if (destination != WsChannel.studentRun(_studentId)) return;
    _unsubscribe = null;
    _forbidden = true;
    state = state.copyWith(connection: LiveMapConnection.forbidden);
  }

  void _onEnvelope(WebSocketEnvelope envelope) {
    if (_runId != null && envelope.runId != _runId) {
      // F05-05 — 같은 자녀 채널로 다음 회차(등원→하원)가 이어져도 앞 회차의 도착·종료 줄이 남지 않게 한다.
      state = LiveMapState(connection: state.connection);
    }
    _runId = envelope.runId;
    switch (envelope.event) {
      case WsEventType.position:
        state = state.copyWith(
          position: WsPositionPayload.fromJson(envelope.payload),
        );
      case WsEventType.stopArrived:
        state = state.copyWith(
          lastStopArrived: WsStopArrivedPayload.fromJson(envelope.payload),
        );
      case WsEventType.runStarted:
        state = state.copyWith(
          runStarted: WsRunStartedPayload.fromJson(envelope.payload),
        );
      case WsEventType.runEnded:
        state = state.copyWith(
          runEnded: WsRunEndedPayload.fromJson(envelope.payload),
        );
      // 이 채널(`studentRun`)에서 나올 수 없는 이벤트 종류
      // (`riderChanged`·`emergency*`·`approvalRequested`)나 서버가 아직
      // 모르는 값(`null`)은 무시한다 — 이 화면의 관심사가 아니다.
      case _:
        break;
    }
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    unawaited(_connectionSub?.cancel());
    unawaited(_forbiddenSub?.cancel());
    super.dispose();
  }
}
