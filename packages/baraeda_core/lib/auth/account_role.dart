/// API_SPEC §9.1 `role` enum — 서버가 아는 역할 전체 6종.
///
/// 앱마다 지원하는 역할은 이 중 일부뿐이다(parent-app: `parent`·`student`,
/// manager-app: `driver`·`escort`). 그 좁은 목록은 각 앱의
/// `core/auth/user_role.dart` 가 따로 갖는다 — 이 타입은 "서버가 준 값을
/// 일단 해석한다"까지만 하고, "이 앱이 그 역할을 지원하는가"는 판단하지
/// 않는다(역할과 상태를 가르는 것과 같은 이유로, 역할 해석과 역할 지원
/// 판정도 서로 다른 관심사라 여기서 합치지 않는다).
enum AccountRole {
  /// 학부모 — parent-app.
  parent('parent'),

  /// 학생 — parent-app.
  student('student'),

  /// 운전기사 — manager-app.
  driver('driver'),

  /// 동승자 — manager-app.
  escort('escort'),

  /// 학원 관리자 — 관계자 웹.
  staff('staff'),

  /// 플랫폼 관리자 — 관계자 웹, `academy` 가 없는 유일한 역할.
  systemAdmin('system_admin');

  new(this.wireValue);

  /// 서버 응답의 `role` 필드 원문 값.
  final String wireValue;

  /// 모르는 값이면 `null` — 서버가 이후 역할을 추가해도 클라이언트가
  /// 죽지 않는다(구 버전 앱과의 호환).
  static AccountRole? fromWireValueOrNull(String? value) {
    for (final role in AccountRole.values) {
      if (role.wireValue == value) return role;
    }
    return null;
  }
}
