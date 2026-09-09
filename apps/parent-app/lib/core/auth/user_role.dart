/// 이 앱이 담는 역할 2종 (IMPLEMENTATION_PLAN.md §1.1). 값은 API_SPEC §9.1
/// `role` enum 과 1:1 — 서버 응답 문자열을 그대로 옮겨 받는다.
enum UserRole {
  parent('parent'),
  student('student');

  const UserRole(this.wireValue);

  /// 서버가 주는 `role` 필드 값.
  final String wireValue;

  static UserRole fromWireValue(String value) => switch (value) {
    'parent' => UserRole.parent,
    'student' => UserRole.student,
    _ => throw ArgumentError('parent-app 이 모르는 role: $value'),
  };
}
