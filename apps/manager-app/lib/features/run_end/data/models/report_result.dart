/// `POST /runs/{runId}/reports` 응답(`201`) — §4.13.
class ReportResult {
  const ReportResult({required this.reportId, required this.reportedAt});

  factory ReportResult.fromJson(Map<String, dynamic> json) {
    return ReportResult(
      reportId: json['report_id'] as String,
      reportedAt: DateTime.parse(json['reported_at'] as String),
    );
  }

  final String reportId;
  final DateTime reportedAt;
}
