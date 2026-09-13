import 'package:parent_app/core/common/json_id.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';

/// `PATCH /students/{id}/runs/{runId}/intent` 응답 (API_SPEC §3.6).
///
/// 3구간 규칙(§1.6·§3.6)의 결과가 여기 담긴다 — 화면은 `RunIntentResult.result`
/// 로 분기하지 구간 이름(①·②·③)을 직접 계산하지 않는다. 구간 판정은
/// 전적으로 서버의 책임이다.
enum RunIntentApplyResult {
  /// ① 구간 — 즉시 반영.
  applied,

  /// ② 구간 — 승인 대기 접수.
  pendingApproval,

  /// ③ 구간 — 반영하되 노선 불변.
  appliedNoReroute;

  static RunIntentApplyResult fromWireValue(String value) => switch (value) {
    'applied' => RunIntentApplyResult.applied,
    'pending_approval' => RunIntentApplyResult.pendingApproval,
    'applied_no_reroute' => RunIntentApplyResult.appliedNoReroute,
    _ => throw ArgumentError('알 수 없는 result: $value'),
  };
}

class RunIntentResult {
  const RunIntentResult({
    required this.result,
    required this.riding,
    required this.riderStatus,
    required this.changeQuotaLeft,
    this.changeRequestId,
    this.deadlineAt,
  });

  factory RunIntentResult.fromJson(Map<String, dynamic> json) =>
      RunIntentResult(
        result: RunIntentApplyResult.fromWireValue(
          json['result'] as String,
        ),
        riding: json['riding'] as bool,
        riderStatus: RiderStatus.fromWireValue(json['rider_status'] as String),
        changeRequestId: json['change_request_id'] == null
            ? null
            : asIdString(json['change_request_id']),
        changeQuotaLeft: json['change_quota_left'] as int,
        deadlineAt: json['deadline_at'] == null
            ? null
            : DateTime.parse(json['deadline_at'] as String),
      );

  final RunIntentApplyResult result;

  /// 반영된 값. `pendingApproval` 이면 기존 값을 유지한 것.
  final bool riding;
  final RiderStatus riderStatus;

  /// `pendingApproval` 일 때만 존재.
  final String? changeRequestId;
  final int changeQuotaLeft;

  /// ② 구간의 승인 마감 = 회차 출발 시각.
  final DateTime? deadlineAt;
}
