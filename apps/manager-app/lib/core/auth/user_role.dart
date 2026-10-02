import 'package:baraeda_core/baraeda_core.dart';

/// 이 앱이 담는 역할 2종 (IMPLEMENTATION_PLAN.md §1.1). 값은 API_SPEC §9.1
/// `role` enum 과 1:1 — 서버 응답 문자열을 그대로 옮겨 받는다.
enum UserRole {
  /// 운전기사.
  driver('driver'),

  /// 동승자.
  escort('escort');

  UserRole(this.wireValue);

  /// 서버가 주는 `role` 필드 값.
  final String wireValue;

  /// 이 앱이 모르는 역할(학부모·학생·관리자 등 다른 앱 계정)이거나 서버가
  /// 아직 모르는 값이면 `null` — 학부모 앱 계정으로 잘못 로그인한 경우가
  /// 실제로 일어날 수 있으므로 [ArgumentError] 로 죽이지 않는다. 화면은
  /// `null` 을 "지원하지 않는 계정" 안내로 갈라야 한다.
  static UserRole? fromWireValueOrNull(String value) {
    final role = AccountRole.fromWireValueOrNull(value);
    return switch (role) {
      AccountRole.driver => UserRole.driver,
      AccountRole.escort => UserRole.escort,
      _ => null,
    };
  }
}
