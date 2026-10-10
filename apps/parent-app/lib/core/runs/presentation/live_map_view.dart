import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/core/runs/domain/bus_position.dart';
import 'package:parent_app/core/runs/domain/live_map_status.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';

/// Ruling 208 — 마지막 수신 후 2분이면 유실로 판정한다. 서버
/// (`API_SPEC §3.11`)의 `StudentBusPositionQueryService.STALE_THRESHOLD`
/// 와 같은 값이어야 한다 — 갈라 두면 REST 스냅샷은 정상인데 WS 화면은
/// 유실로 보이는(또는 그 반대) 구간이 생긴다.
const positionStaleThreshold = Duration(minutes: 2);

/// 실시간 위치 화면이 지금 그리는 모양 — 시안 `live-map*` 7장이 이 값 하나로 갈린다.
///
/// 순서가 판정 우선순위다. 같은 때 둘 이상이 참이면 앞의 것이 이긴다
/// (예: 결석은 연결이 살아 있어도 뒤집히지 않고, 운행 종료는 방송이 멎어 좌표가 2분을 넘겨도 "신호 없음"이 되지 않는다).
enum LiveMapPhase {
  /// 당일 결석(§3.11) — 지도 없이 안내만.
  absent,

  /// 연결 상태 판정 중이거나 §3.11 첫 스냅샷을 기다리는 중 — 시트 뼈대만.
  loading,

  /// 연결 끊김(재시도 상한) 또는 구독 권한 거절 — "데이터 없음"과 겹치지 않도록 가장 먼저 가른다(완료 조건 9).
  disconnected,

  /// 운행이 끝났다.
  ended,

  /// 위치를 받다가 2분 넘게 끊겼다 — "마지막 확인 위치 · N분 전".
  noSignal,

  /// 아직 출발 전 — 지도 대신 출발 시각 안내.
  before,

  /// 달리는 중 — 지도 + 이동 중 시트. 좌표가 아직 없으면 "위치 신호 대기 중".
  tracking,
}

/// 화면이 그릴 값을 모은 것 — `LiveMapState`(연결 · 이벤트 · 스냅샷)와 지금 시각에서 **순수 계산**으로만 만든다.
class LiveMapView {
  const new({
    required this.phase,
    this.forbidden = false,
    this.reconnecting = false,
    this.position,
    this.positionAt,
    this.staleMinutes,
    this.lastSeenAt,
    this.startedAt,
    this.finishedAt,
    this.delay,
    this.lastStopName,
    this.lastStopArrivedAt,
    this.busNo,
    this.run,
    this.runId,
  });

  /// 상태 한 벌로부터 화면 모양을 정한다. [now] 는 `clockProvider` 의 시각 — 유실 판정이 서버와 같은 시계를 쓰게
  /// 한다.
  factory resolve(LiveMapState state, DateTime now) {
    final connection = state.connection;
    final rest = switch (state.restPosition) {
      AsyncData<BusPosition>(:final value) => value,
      _ => null,
    };
    final restLoading = state.restPosition is AsyncLoading<BusPosition>;

    // R48 `Ruling 821` — §3.11 스냅샷이 주는 지연 안내 · 운행 시작/종료 시각. WebSocket
    // 이벤트(`run_started` ·
    // `run_ended`)를 놓치고 들어와도 시각이 비지 않게, 이벤트가 있으면 이벤트를 쓰고 없으면 스냅샷을 쓴다.
    final ended =
        state.runEnded != null || rest?.runStatus == RunStatus.finished;
    final delay = ended ? null : rest?.delay;
    final startedAt = state.runStarted?.startedAt ?? rest?.startedAt;
    final finishedAt = state.runEnded?.finishedAt ?? rest?.finishedAt;

    // 스냅샷이 좌표를 줬는데 WS 는 아직 못 받았다면 스냅샷으로 메운다 — `receivedAt` 이 없으면(서버가 시각을 안 줌)
    // 합성하지 않는다. `eta` 는 채우지 않는다(§7.1 — 학부모·학생 채널은 ETA 를 절대 받지 않는다, C-08).
    final restPosition =
        state.position == null &&
            rest != null &&
            rest.lat != null &&
            rest.lng != null &&
            rest.receivedAt != null
        ? WsPositionPayload(
            lat: rest.lat!,
            lng: rest.lng!,
            receivedAt: rest.receivedAt!,
            currentStopName: rest.currentStopName,
          )
        : null;
    final position = state.position ?? restPosition;

    // 신호 유실(Ruling 208 — 마지막 수신 후 2분). 서버가 좌표 없이 `last_seen_at` 만 준 경우와, 좌표를 한
    // 번 받은 뒤
    // 방송만 멎어 그 좌표가 2분을 넘긴 경우(Ruling 349) 둘 다 유실이다. `run_status` 가 `moving` 이
    // 아니면서
    // `last_seen_at` 도 없는 것은 유실이 아니라 그냥 운행 전·후 상태다.
    final restLostAt =
        state.position == null &&
            rest != null &&
            rest.lat == null &&
            rest.lastSeenAt != null
        ? rest.lastSeenAt
        : null;
    final positionStale =
        position != null &&
        now.difference(position.receivedAt) >= positionStaleThreshold;
    final lastSeenAt =
        restLostAt ?? (positionStale ? position.receivedAt : null);
    final staleMinutes = lastSeenAt == null
        ? null
        : now.difference(lastSeenAt).inMinutes;

    final stopArrived = state.lastStopArrived;
    final lastStopName = stopArrived?.name ?? position?.currentStopName;
    final lastStopArrivedAt =
        stopArrived?.arrivedAt ??
        (position?.currentStopName == null ? null : rest?.currentStopArrivedAt);

    LiveMapView build(
      LiveMapPhase phase, {
      WsPositionPayload? drawn,
      DateTime? positionAt,
    }) => LiveMapView(
      phase: phase,
      forbidden: connection == LiveMapConnection.forbidden,
      reconnecting: connection == LiveMapConnection.reconnecting,
      position: drawn,
      positionAt: positionAt,
      staleMinutes: staleMinutes,
      lastSeenAt: lastSeenAt,
      startedAt: startedAt,
      finishedAt: finishedAt,
      delay: delay,
      lastStopName: lastStopName,
      lastStopArrivedAt: lastStopArrivedAt,
      busNo: rest?.busNo ?? state.run?.busNo,
      run: state.run,
      runId: rest?.runId ?? state.run?.runId,
    );

    if (state.isAbsent) return build(LiveMapPhase.absent);
    if (connection.isLost) {
      return build(
        LiveMapPhase.disconnected,
        drawn: position,
        positionAt: position?.receivedAt,
      );
    }
    // 스피너는 첫 진입의 첫 연결 시도 · 첫 스냅샷에만 쓴다 — 아무것도 못 받은 동안 "출발 전"이 먼저 깜빡이지 않게.
    if (connection.isLoading || (restLoading && state.hasNoData)) {
      return build(LiveMapPhase.loading);
    }
    if (ended || finishedAt != null) {
      return build(LiveMapPhase.ended, drawn: position);
    }
    if (staleMinutes != null) {
      return build(
        LiveMapPhase.noSignal,
        drawn: positionStale ? position : null,
      );
    }
    if (position != null) {
      return build(
        LiveMapPhase.tracking,
        drawn: position,
        positionAt: position.receivedAt,
      );
    }
    final beforeDeparture =
        rest == null ||
        rest.runStatus == RunStatus.idle ||
        rest.runStatus == RunStatus.confirmed;
    if (state.hasNoData && beforeDeparture && startedAt == null) {
      return build(LiveMapPhase.before);
    }
    return build(LiveMapPhase.tracking);
  }

  final LiveMapPhase phase;

  /// 구독 권한 거절로 끊긴 것 — 다시 해도 같은 결과라 [다시 시도] 를 두지 않는다.
  final bool forbidden;

  /// 끊겨서 자동 재연결 중(좌표는 마지막 값 그대로).
  final bool reconnecting;

  /// 지도에 그릴 버스 좌표. `tracking` 은 2분 안의 좌표, `noSignal`·`disconnected`·`ended` 는
  /// 마지막 좌표(있을 때만).
  final WsPositionPayload? position;

  /// 마지막으로 좌표를 받은 시각 — "12:14 기준" · "마지막 갱신 12:11".
  final DateTime? positionAt;

  /// `noSignal` 의 "N분 전".
  final int? staleMinutes;

  /// `noSignal` 의 "마지막으로 확인한 시각".
  final DateTime? lastSeenAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  /// 지연 띠 — `null` 이면 그리지 않는다.
  final BusDelay? delay;

  /// "마지막으로 지난 곳" 이름 · 도착 시각. 시각은 서버가 줄 때만 있다.
  final String? lastStopName;
  final DateTime? lastStopArrivedAt;

  /// 스냅샷이 준 호차, 없으면 회차 목록의 호차.
  final String? busNo;

  /// 오늘 회차(방향 · 출발 시각 · 확정 여부). 회차 목록을 못 받았으면 `null`.
  final StudentRun? run;

  /// 지금 보는 회차의 식별자 — 스냅샷이 준 값, 없으면 회차 목록의 값. 노선(§3.10)을 같은 회차로 읽는 데 쓴다.
  /// 둘 다 없으면 `null`(서버 기본값 — 당일 다음 회차).
  final String? runId;
}

/// 지도 시트와 홈 미리보기가 같이 쓰는 상태 칩 — 칩 문구를 두 곳에서 따로 정하지 않는다(R52 M2).
/// 시트를 그리지 않는 모양(`absent` · `before` · `loading`)은 부르는 쪽이 따로 정한다.
extension LiveMapViewChip on LiveMapView {
  ({BaraedaStatus status, String label}) get chip => switch (phase) {
    LiveMapPhase.tracking => (status: BaraedaStatus.moving, label: '이동 중'),
    LiveMapPhase.noSignal => (status: BaraedaStatus.idle, label: '신호 없음'),
    LiveMapPhase.ended => (status: BaraedaStatus.idle, label: '종료'),
    LiveMapPhase.disconnected when forbidden => (
      status: BaraedaStatus.idle,
      label: '볼 수 없음',
    ),
    _ => (status: BaraedaStatus.idle, label: '연결 끊김'),
  };
}
