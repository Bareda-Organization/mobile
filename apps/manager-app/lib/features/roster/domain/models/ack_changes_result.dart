/// `POST /runs/{runId}/ack-changes` 응답 — §4.11(M-04).
class AckChangesResult {
  const new({required this.ackedAt});

  factory fromJson(Map<String, dynamic> json) {
    return AckChangesResult(
      ackedAt: DateTime.parse(json['acked_at'] as String),
    );
  }

  final DateTime ackedAt;
}
