/// `POST /runs/{runId}/emergency` 응답(`201`) — §4.14.
///
/// `cancelableUntil` 은 반드시 이 응답에서만 받는다 — 클라이언트가
/// `raisedAt + 1분` 으로 계산하면 단말·서버 시계가 어긋났을 때(clock skew)
/// 취소 가능 창을 실제와 다르게 보여준다.
class EmergencyRaiseResult {
  const EmergencyRaiseResult({
    required this.emergencyId,
    required this.raisedAt,
    required this.cancelableUntil,
    required this.notified,
  });

  factory EmergencyRaiseResult.fromJson(Map<String, dynamic> json) {
    return EmergencyRaiseResult(
      emergencyId: json['emergency_id'] as String,
      raisedAt: DateTime.parse(json['raised_at'] as String),
      cancelableUntil: DateTime.parse(json['cancelable_until'] as String),
      notified: json['notified'] as int,
    );
  }

  final String emergencyId;
  final DateTime raisedAt;
  final DateTime cancelableUntil;

  /// 수신자 수.
  final int notified;
}
