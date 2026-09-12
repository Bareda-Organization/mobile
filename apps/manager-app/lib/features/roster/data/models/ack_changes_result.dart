/// `POST /runs/{runId}/ack-changes` 응답 — §4.11(M-04).
class AckChangesResult {
  const AckChangesResult({required this.ackedAt});

  factory AckChangesResult.fromJson(Map<String, dynamic> json) {
    return AckChangesResult(
      ackedAt: DateTime.parse(json['acked_at'] as String),
    );
  }

  final DateTime ackedAt;
}
