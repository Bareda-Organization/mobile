import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/auth/role_policy.dart';
import 'package:manager_app/core/auth/user_role.dart';

/// 역할 권한 판정(RoleCapabilities.of) 시험 — 같은 StopRoster 화면에서
/// 버튼 노출이 갈리는 판단이 여기 한곳에서 맞게 나오는지 확인한다
/// (IMPLEMENTATION_PLAN.md §1.1).
void main() {
  group('RoleCapabilities.of(driver)', () {
    final capabilities = RoleCapabilities.of(UserRole.driver);

    test('도착 알림 전송 가능', () {
      expect(capabilities.canSendArrivalNotification, isTrue);
    });

    test('지연 알림 전송 가능', () {
      expect(capabilities.canSendDelayNotification, isTrue);
    });

    test('개인별 승하차 상태 결정 불가 — 동승자 전용', () {
      expect(capabilities.canDecideBoardingStatus, isFalse);
    });
  });

  group('RoleCapabilities.of(escort)', () {
    final capabilities = RoleCapabilities.of(UserRole.escort);

    test('도착 알림 전송 불가 — 기사 전용', () {
      expect(capabilities.canSendArrivalNotification, isFalse);
    });

    test('지연 알림 전송 불가 — 기사 전용', () {
      expect(capabilities.canSendDelayNotification, isFalse);
    });

    test('개인별 승하차 상태 결정 가능', () {
      expect(capabilities.canDecideBoardingStatus, isTrue);
    });
  });

  test('UserRole.fromWireValue 는 서버 role 문자열을 왕복 변환한다', () {
    expect(UserRole.fromWireValue('driver'), UserRole.driver);
    expect(UserRole.fromWireValue('escort'), UserRole.escort);
  });
}
