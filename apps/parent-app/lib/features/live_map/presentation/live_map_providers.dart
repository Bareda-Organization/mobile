import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/features/live_map/domain/live_map_status.dart';

/// `studentId` 별 실시간 위치 화면 상태 — `/topic/students/{studentId}/run`
/// 하나만 구독한다(공용 `webSocketClientProvider`, §1 판단 근거: 학부모가
/// 한 번에 볼 수 있는 자녀는 `selectedStudentIdProvider` 로 정확히 하나라
/// 여러 목적지를 동시에 구독할 일이 설계상 없다 — COMMON.md 의 과다신고
/// 조항이 걸리지 않는다).
///
/// `autoDispose.family` — 화면을 벗어나거나 자녀를 전환하면 이전
/// `studentId` 의 인스턴스가 해제되며 구독도 함께 해지된다.
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

  BaraedaWebSocketClient get _client => _ref.read(webSocketClientProvider);

  void _init() {
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
  }

  void _onConnectionState(WsConnectionState wsState) {
    _applyConnectionState(wsState);
    if (wsState == WsConnectionState.connected && _unsubscribe == null) {
      _subscribe(_client);
    }
  }

  void _applyConnectionState(WsConnectionState wsState) {
    final connection = switch (wsState) {
      WsConnectionState.disconnected => LiveMapConnection.idle,
      WsConnectionState.connecting => LiveMapConnection.connecting,
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
    state = state.copyWith(connection: LiveMapConnection.forbidden);
  }

  void _onEnvelope(WebSocketEnvelope envelope) {
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
