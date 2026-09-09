/// `POST /auth/signup` 요청 (API_SPEC §2.2).
class SignupRequest {
  /// 필드 6개 전부 필수(§2.2 요청 표에 선택값 없음).
  const SignupRequest({
    required this.role,
    required this.loginId,
    required this.password,
    required this.name,
    required this.phone,
    required this.academyId,
  });

  /// 서버 `role` enum 원문 값 — `parent`·`student`·`driver`·`escort`·`staff`.
  /// 여기서는 문자열로 받는다: 이 클래스는 어느 앱이 호출해도 같은 모양이어야
  /// 하는데 `AccountRole` 전체 6종 중 앱마다 쓸 수 있는 부분집합이 다르다.
  final String role;

  /// 로그인 아이디. 중복 시 `409 DUPLICATE_LOGIN_ID`.
  final String loginId;

  /// 비밀번호.
  final String password;

  /// 이름.
  final String name;

  /// 연락처 — 아이디·비밀번호 복구의 인증 수단(AUTH-08).
  final String phone;

  /// `GET /academies/search` 결과의 `id`.
  final String academyId;

  /// 요청 본문으로 직렬화.
  Map<String, dynamic> toJson() => {
    'role': role,
    'login_id': loginId,
    'password': password,
    'name': name,
    'phone': phone,
    'academy_id': academyId,
  };
}

/// `POST /auth/signup` 의 `201` 응답.
class SignupResponse {
  /// 필드 3개 전부 서버가 채워 보낸다.
  const SignupResponse({
    required this.accountStatus,
    required this.requestedAt,
    required this.approver,
  });

  /// 응답 본문을 그대로 옮긴다.
  factory SignupResponse.fromJson(Map<String, dynamic> json) => SignupResponse(
    accountStatus: json['account_status'] as String,
    requestedAt: DateTime.parse(json['requested_at'] as String),
    approver: json['approver'] as String,
  );

  /// `pending` 고정.
  final String accountStatus;

  /// 신청 일시.
  final DateTime requestedAt;

  /// `staff`(관계자 승인) · `system_admin`(메인 관리자 승인). `role=staff` 는
  /// `system_admin`.
  final String approver;
}
