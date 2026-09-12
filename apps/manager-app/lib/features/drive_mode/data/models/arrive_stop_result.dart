import 'package:manager_app/core/run/run_enums.dart';

/// `remaining[]` 항목 — 하원 종료 보류 중 아직 안 내린 탑승자.
class RemainingRider {
  const RemainingRider({
    required this.riderId,
    required this.name,
    required this.stopName,
  });

  factory RemainingRider.fromJson(Map<String, dynamic> json) {
    return RemainingRider(
      riderId: json['rider_id'] as String,
      name: json['name'] as String,
      stopName: json['stop_name'] as String,
    );
  }

  final String riderId;
  final String name;
  final String stopName;
}

/// `next_stop` 요약 — 포인터가 가리키는 다음 승하차지.
class NextStopRef {
  const NextStopRef({required this.stopId, required this.name});

  factory NextStopRef.fromJson(Map<String, dynamic> json) {
    return NextStopRef(
      stopId: json['stop_id'] as String,
      name: json['name'] as String,
    );
  }

  final String stopId;
  final String name;
}

/// `POST /runs/{runId}/stops/{stopId}/arrive` 응답 (API_SPEC §4.5, RUN-04 ·
/// M-11). §4.10 이 설명하는 "전용 종료 API 부재" 를 실제로 겪는 지점 —
/// [isFinal]·[finishPending]·[remaining] 세 값을 조합해 RunEndScreen 이
/// 종료 상태를 재구성한다.
class ArriveStopResult {
  const ArriveStopResult({
    required this.arrivedAt,
    required this.isFinal,
    required this.runStatus,
    required this.finishPending,
    required this.remaining,
    this.nextStop,
    this.autoAlightedCount,
  });

  factory ArriveStopResult.fromJson(Map<String, dynamic> json) {
    final nextStopJson = json['next_stop'] as Map<String, dynamic>?;
    final remainingJson = json['remaining'] as List<dynamic>? ?? [];
    return ArriveStopResult(
      arrivedAt: DateTime.parse(json['arrived_at'] as String),
      nextStop: nextStopJson == null
          ? null
          : NextStopRef.fromJson(nextStopJson),
      isFinal: json['is_final'] as bool,
      runStatus:
          RunStatus.fromWireValueOrNull(json['run_status'] as String?) ??
          RunStatus.moving,
      finishPending: json['finish_pending'] as bool? ?? false,
      remaining: remainingJson
          .cast<Map<String, dynamic>>()
          .map(RemainingRider.fromJson)
          .toList(),
      autoAlightedCount: json['auto_alighted_count'] as int?,
    );
  }

  final DateTime arrivedAt;

  /// 전진된 다음 승하차지 — 마지막 지점 도착이면 `null`.
  final NextStopRef? nextStop;

  /// 최종 지점 도착 여부(C-15).
  final bool isFinal;
  final RunStatus runStatus;

  /// 하원 잔류로 종료가 보류된 상태 — `true` 면 §4.6 의 마지막 `alighted`
  /// 가 서버 쪽에서 자동으로 `finished` 전이를 일으킬 때까지 기다린다.
  final bool finishPending;

  /// [finishPending] 일 때 남은 탑승자 — RunEndScreen 이 "하차 대기" 로 보여준다.
  final List<RemainingRider> remaining;

  /// 등원 종료 시 전원 자동 `alighted` 처리된 인원(C-07).
  final int? autoAlightedCount;
}
