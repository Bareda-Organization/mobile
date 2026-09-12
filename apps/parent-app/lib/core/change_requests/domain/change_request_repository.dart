import 'package:parent_app/core/change_requests/domain/change_request.dart';

/// 화면이 보는 일일 변경 신청 계약 — §3.8·§3.9.
abstract interface class ChangeRequestRepository {
  /// §3.8. `type=relocate` 면 [newAddress] 필수(서버가 검증, 클라이언트는
  /// 요청만 조립).
  Future<ChangeRequestCreateResult> createChangeRequest(
    String studentId, {
    required ChangeRequestType type,
    required String runId,
    String? newAddress,
    String? reason,
  });

  /// §3.9 — `pending_count` 는 홈 배지용.
  Future<ChangeRequestPage> getChangeRequests(String studentId);
}
