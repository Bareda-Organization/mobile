import 'package:baraeda_core/baraeda_core.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';

/// `PATCH /runs/{runId}/riders/{riderId}` 응답 — §4.6.
class RiderUpdateResult {
  const new({
    required this.riderId,
    required this.status,
    required this.changedAt,
    required this.stopSkipped,
    this.noShowCase,
  });

  factory fromJson(Map<String, dynamic> json) {
    final noShowCaseJson = json['no_show_case'] as Map<String, dynamic>?;
    return RiderUpdateResult(
      // `Ruling 275` — 서버가 rider_id 를 int 로 내려도 흡수한다(직접 캐스트 금지).
      riderId: asIdString(json['rider_id']),
      status:
          RiderStatus.fromWireValueOrNull(json['status'] as String?) ??
          RiderStatus.waiting,
      changedAt: DateTime.parse(json['changed_at'] as String),
      stopSkipped: json['stop_skipped'] as bool? ?? false,
      noShowCase: noShowCaseJson == null
          ? null
          : NoShowCase.fromJson(noShowCaseJson),
    );
  }

  final String riderId;
  final RiderStatus status;
  final DateTime changedAt;

  /// 잔여 탑승자 0명 전환 여부(C-05) — 정류장이 자동으로 `skipped` 로
  /// 바뀌었다는 신호. StopRoster 가 UI 새로고침 트리거로 쓴다.
  final bool stopSkipped;
  final NoShowCase? noShowCase;
}
