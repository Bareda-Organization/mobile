import 'package:baraeda_core/auth/account_role.dart';
import 'package:baraeda_core/auth/account_status.dart';
import 'package:baraeda_core/auth/models/academy_ref.dart';

/// `POST /auth/login` 응답 (API_SPEC §2.5).
///
/// `refreshToken` 은 `X-Client-Type: app` 일 때만 본문에 담긴다 — 웹은
/// `Set-Cookie` 로 오므로 이 필드가 `null` 이다. 두 앱은 전부 `app` 이라
/// 실제로는 항상 채워지지만, 사양이 명시한 대로 nullable 로 둔다.
class LoginResponse {
  /// [refreshToken]·[academy] 만 선택값 — 각각 웹 클라이언트 · `system_admin`
  /// 로그인일 때 `null`.
  const LoginResponse({
    required this.accessToken,
    required this.role,
    required this.status,
    required this.accountId,
    this.refreshToken,
    this.academy,
    this.mustChangePassword = false,
  });

  /// 응답 본문을 그대로 옮긴다.
  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    final academyJson = json['academy'] as Map<String, dynamic>?;
    return LoginResponse(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      role: AccountRole.fromWireValueOrNull(json['role'] as String?),
      status: AccountStatus.fromWireValueOrNull(json['status'] as String?),
      accountId: json['account_id'] as String,
      academy: academyJson == null ? null : AcademyRef.fromJson(academyJson),
      mustChangePassword: json['must_change_password'] as bool? ?? false,
    );
  }

  /// 단기 토큰. 앱·웹 공통으로 본문에 담긴다.
  final String accessToken;

  /// 장기 토큰 — `app` 클라이언트일 때만 본문에 담긴다.
  final String? refreshToken;

  /// `null` 이면 이 앱이 모르는 역할 — 화면이 "지원하지 않는 계정" 안내로
  /// 갈라야 한다(user_role.dart 의 `fromWireValue` 가 죽지 않게 하는 것과
  /// 같은 이유).
  final AccountRole? role;

  /// `pending` · `active` · `rejected`.
  final AccountStatus? status;

  /// 계정 식별자.
  final String accountId;

  /// `system_admin` 은 `null`.
  final AcademyRef? academy;

  /// 임시 비밀번호 강제 변경 표식(API_SPEC §2.5, Ruling 540) — 관리자가 비밀번호를 초기화한 계정이면 `true`.
  /// 서버는 이 계정이 비밀번호를 바꾸기 전까지 다른 API 를 `403 PASSWORD_CHANGE_REQUIRED` 로 막는다.
  final bool mustChangePassword;
}
