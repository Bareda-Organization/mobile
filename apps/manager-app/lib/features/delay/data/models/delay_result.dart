/// `POST /runs/{runId}/delay` 응답(`201`) — §4.9.
class DelayResult {
  const DelayResult({
    required this.notifiedGuardians,
    required this.notifiedStudents,
    required this.notifiedStaff,
  });

  factory DelayResult.fromJson(Map<String, dynamic> json) {
    return DelayResult(
      notifiedGuardians: json['notified_guardians'] as bool,
      notifiedStudents: json['notified_students'] as bool,
      notifiedStaff: json['notified_staff'] as bool,
    );
  }

  final bool notifiedGuardians;
  final bool notifiedStudents;
  final bool notifiedStaff;
}
