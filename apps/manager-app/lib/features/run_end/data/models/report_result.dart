import 'package:baraeda_core/baraeda_core.dart';

/// `POST /runs/{runId}/reports` 응답(`201`) — §4.13.
class ReportResult {
  const ReportResult({required this.reportId, required this.reportedAt});

  factory ReportResult.fromJson(Map<String, dynamic> json) {
    return ReportResult(
      // `Ruling 275` — 서버가 report_id 를 int 로 내려도 흡수한다(직접 캐스트 금지).
      reportId: asIdString(json['report_id']),
      reportedAt: DateTime.parse(json['reported_at'] as String),
    );
  }

  final String reportId;
  final DateTime reportedAt;
}
