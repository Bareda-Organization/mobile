import 'package:manager_app/core/run/run_enums.dart';

/// `POST /runs/{runId}/start` 응답 (API_SPEC §4.4, RUN-02 · M-10).
class StartRunResult {
  const new({
    required this.runStatus,
    required this.startedAt,
    this.autoBoardedCount,
  });

  factory fromJson(Map<String, dynamic> json) {
    return StartRunResult(
      runStatus:
          RunStatus.fromWireValueOrNull(json['run_status'] as String?) ??
          RunStatus.moving,
      startedAt: DateTime.parse(json['started_at'] as String),
      autoBoardedCount: json['auto_boarded_count'] as int?,
    );
  }

  final RunStatus runStatus;
  final DateTime startedAt;

  /// 하원일 때만 값이 있다 — 탑승자 전원이 자동 `boarded` 처리된 인원(C-07).
  final int? autoBoardedCount;
}
