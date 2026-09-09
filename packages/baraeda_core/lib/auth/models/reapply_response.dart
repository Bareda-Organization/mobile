import 'package:baraeda_core/auth/account_status.dart';

/// `POST /auth/signup/reapply` 응답 (API_SPEC §2.4) — 성공 시 `status` 는
/// 항상 `pending` 으로 되돌아간다.
class ReapplyResponse {
  /// 필드 2개 전부 서버가 채워 보낸다.
  const ReapplyResponse({required this.status, required this.requestedAt});

  /// 응답 본문을 그대로 옮긴다.
  factory ReapplyResponse.fromJson(Map<String, dynamic> json) =>
      ReapplyResponse(
        status:
            AccountStatus.fromWireValueOrNull(json['status'] as String?) ??
            AccountStatus.pending,
        requestedAt: DateTime.parse(json['requested_at'] as String),
      );

  /// 재신청 성공 시 항상 `pending`.
  final AccountStatus status;

  /// 재신청 일시.
  final DateTime requestedAt;
}
