import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/auth/role_policy.dart';
import 'package:parent_app/core/auth/user_role.dart';

/// 역할 권한 판정(RoleCapabilities.of) 시험 — 화면 진입점을 감추는 판단이
/// 여기 한곳에서 맞게 나오는지 확인한다(IMPLEMENTATION_PLAN.md §1.1).
void main() {
  group('RoleCapabilities.of(parent)', () {
    final capabilities = RoleCapabilities.of(UserRole.parent);

    test('등원 여부 변경 가능', () {
      expect(capabilities.canToggleAttendance, isTrue);
    });

    test('탑승 위치 변경 가능', () {
      expect(capabilities.canChangeBoardingLocation, isTrue);
    });

    test('부모 연결 코드 생성 불가 (S-05 는 학생 전용)', () {
      expect(capabilities.canGenerateLinkCode, isFalse);
    });
  });

  group('RoleCapabilities.of(student)', () {
    final capabilities = RoleCapabilities.of(UserRole.student);

    test('등원 여부 변경 불가 — 학생은 조회 전용', () {
      expect(capabilities.canToggleAttendance, isFalse);
    });

    test('탑승 위치 변경 불가 — 학생은 조회 전용', () {
      expect(capabilities.canChangeBoardingLocation, isFalse);
    });

    test('부모 연결 코드 생성 가능 (S-05, 학생의 유일한 쓰기 권한)', () {
      expect(capabilities.canGenerateLinkCode, isTrue);
    });
  });

  test('UserRole.fromWireValue 는 서버 role 문자열을 왕복 변환한다', () {
    expect(UserRole.fromWireValue('parent'), UserRole.parent);
    expect(UserRole.fromWireValue('student'), UserRole.student);
  });
}
