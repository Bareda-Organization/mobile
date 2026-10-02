/// API_SPEC §2.3·§2.5·§2.10 의 `status` 값 — `pending → active` ·
/// `pending → rejected → (재신청) → pending`.
///
/// `blocked` 은 이 enum에 없다 — 로그인 5회 실패로 걸리는 계정 차단은
/// 로그인 응답의 `status` 필드가 아니라 `403 AUTH_ACCOUNT_BLOCKED` 에러로만
/// 나타난다(§2.5). 즉 `blocked` 은 "로그인은 됐지만 상태가 이렇다"가 아니라
/// "로그인 자체가 안 된다"이므로, 로그인 이후에만 의미가 있는 이 enum에
/// 넣지 않는다 — role_policy.dart 와 상태 게이트를 분리한 것과 같은 이유로,
/// 로그인 가능 여부와 로그인 후 상태도 서로 다른 것을 가른다.
enum AccountStatus {
  /// 가입 승인 대기 — 로그인은 되지만 좁은 허용 목록만 호출 가능.
  pending('pending'),

  /// 승인 완료 — 정상 이용.
  active('active'),

  /// 승인 거절 — 재신청(§2.4)으로 [pending] 으로 되돌아갈 수 있다.
  rejected('rejected');

  AccountStatus(this.wireValue);

  /// 서버 응답의 `status` 필드 원문 값.
  final String wireValue;

  /// 모르는 값이면 `null`.
  static AccountStatus? fromWireValueOrNull(String? value) {
    for (final status in AccountStatus.values) {
      if (status.wireValue == value) return status;
    }
    return null;
  }
}
