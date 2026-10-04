import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/core/runs/domain/bus_position.dart';

/// 화면이 실제로 그리는 연결 판정 — `WsConnectionState` 를 화면 관점으로
/// 좁힌 것. "데이터 없음"과 "연결 끊김"을 구별하는 것이 이 화면의 완료
/// 조건 9(공유 목표)라, `WsConnectionState` 를 그대로 노출하지 않고
/// 화면이 렌더링 분기에 쓸 이름으로 한 번 더 감싼다.
enum LiveMapConnection {
  /// 아직 연결을 시도하지 않았다 — 최초 진입 직후.
  idle,

  /// CONNECT 프레임을 보내고 서버 응답을 기다리는 중.
  connecting,

  /// 구독까지 마치고 이벤트를 받을 준비가 된 상태.
  connected,

  /// 연결이 끊어져 자동 재시도 중 — `WsConnectionState.reconnecting`.
  reconnecting,

  /// 재시도 상한 도달 — `WsConnectionState.gaveUp`. "데이터 없음"이
  /// 아니라 "연결 끊김"으로 표시해야 하는 자리. 기본 재연결 정책은 상한이
  /// 없어(R46-FIXRT S-5) 운영에서는 이 상태에 들지 않는다.
  gaveUp,

  /// 이 학생 회차 채널 구독이 서버에서 거부됨(FORBIDDEN) — 연결 자체는
  /// 살아있어도 이 화면은 데이터를 받을 수 없다.
  forbidden;

  /// `!isUsable` 이 곧 "연결 끊김" 표시 조건 — FE-R2 목표1의 `!error`
  /// 가드와 같은 자리에 쓴다(§4 참고). `idle`·`connecting` 은 아직
  /// 실패로 확정되지 않았으므로 "데이터 없음"도 "연결 끊김"도 아니고
  /// 로딩으로 그린다.
  bool get isUsable =>
      this == LiveMapConnection.connected ||
      this == LiveMapConnection.reconnecting;

  bool get isLoading =>
      this == LiveMapConnection.idle || this == LiveMapConnection.connecting;

  bool get isLost =>
      this == LiveMapConnection.gaveUp || this == LiveMapConnection.forbidden;
}

/// 화면 상태 전체 — 4개 이벤트(`position`·`stop_arrived`·`run_started`·
/// `run_ended`)를 각자의 최신값으로만 쌓는다. 지도 위젯은 F4-B 몫이라
/// 좌표를 그리지 않고, 여기서는 값을 들고 있기만 한다.
class LiveMapState {
  const new({
    this.connection = LiveMapConnection.idle,
    this.position,
    this.lastStopArrived,
    this.runStarted,
    this.runEnded,
    this.restPosition,
    this.isAbsent = false,
  });

  final LiveMapConnection connection;
  final WsPositionPayload? position;
  final WsStopArrivedPayload? lastStopArrived;
  final WsRunStartedPayload? runStarted;
  final WsRunEndedPayload? runEnded;

  /// API_SPEC §3.11 첫 진입 스냅샷 — WS 와 별개로 한 번만 불러온다
  /// (`live_map_providers.dart` 의 `_loadRestSnapshot` 참고). `null` 은
  /// "아직 요청을 시작하지 않음"이고, 요청이 걸리면 곧바로
  /// `AsyncValue.loading()` 으로 바뀐다 — 화면은 이 값을 WS 가 아직
  /// 아무것도 안 준 첫 프레임의 대체 표시로만 쓰고, `position`(WS) 이
  /// 오면 그쪽을 우선한다.
  final AsyncValue<BusPosition>? restPosition;

  /// 당일 `RiderStatus.absent` 대조 결과(`runsForStudentProvider` 와
  /// `restPosition.runId` 를 맞춰 본다) — §3.11 응답 자체에는 결석 여부
  /// 필드가 없어 별도로 들고 있어야 한다.
  final bool isAbsent;

  /// "표시할 이벤트가 아직 하나도 없다" — 4종 이벤트(`position`·
  /// `stop_arrived`·`run_started`·`run_ended`) 전부가 비어야 참이다.
  /// `run_started` 만 와도 화면은 그 타일을 그려야 하므로 `position`·
  /// `lastStopArrived` 만 보면 안 된다 — 실제로 위젯 시험에서
  /// `run_started` 단독 수신 시 "데이터 없음" 화면이 잘못 뜨는 결함으로
  /// 드러났다. 화면은 `connection.isLost` 를 먼저 검사해야 이 값과
  /// 겹치지 않는다(목표 9).
  bool get hasNoData =>
      position == null &&
      lastStopArrived == null &&
      runStarted == null &&
      runEnded == null;

  LiveMapState copyWith({
    LiveMapConnection? connection,
    WsPositionPayload? position,
    WsStopArrivedPayload? lastStopArrived,
    WsRunStartedPayload? runStarted,
    WsRunEndedPayload? runEnded,
    AsyncValue<BusPosition>? restPosition,
    bool? isAbsent,
  }) {
    return LiveMapState(
      connection: connection ?? this.connection,
      position: position ?? this.position,
      lastStopArrived: lastStopArrived ?? this.lastStopArrived,
      runStarted: runStarted ?? this.runStarted,
      runEnded: runEnded ?? this.runEnded,
      restPosition: restPosition ?? this.restPosition,
      isAbsent: isAbsent ?? this.isAbsent,
    );
  }
}
