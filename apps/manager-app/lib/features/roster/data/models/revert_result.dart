import 'package:manager_app/core/run/run_enums.dart';

/// `POST /runs/{runId}/riders/{riderId}/revert` 응답 — §4.7.
class RevertResult {
  const RevertResult({required this.status, required this.revertedAt});

  factory RevertResult.fromJson(Map<String, dynamic> json) {
    return RevertResult(
      status:
          RiderStatus.fromWireValueOrNull(json['status'] as String?) ??
          RiderStatus.waiting,
      revertedAt: DateTime.parse(json['reverted_at'] as String),
    );
  }

  /// 되돌린 값.
  final RiderStatus status;
  final DateTime revertedAt;
}
