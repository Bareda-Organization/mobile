import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/features/auth/presentation/login_screen.dart';
import 'package:manager_app/features/position/presentation/position_transmitter.dart';

void main() {
  /// 세션 만료 처리를 provider 안에서 부르는 통로 — 함수가 `Ref` 를 받는다.
  final endExpired = Provider<void Function()>(
    (ref) =>
        () => endSessionAsExpired(ref),
  );

  group('endSessionAsExpired (R46)', () {
    test('로그인이 풀리면 역할을 비우고 "로그인이 만료됐습니다" 안내를 남긴다', () {
      final container = ProviderContainer(
        overrides: [
          currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
        ],
      );
      addTearDown(container.dispose);

      container.read(endExpired)();

      expect(container.read(currentUserRoleProvider), isNull);
      expect(
        container.read(sessionExpiredNoticeProvider),
        '로그인이 만료됐습니다. 다시 로그인해 주세요',
      );
    });

    test('위치를 보내던 기사가 만료되면 위치 전송이 멈췄다는 경고를 더한다', () {
      final container = ProviderContainer(
        overrides: [
          currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
          transmittingRunIdProvider.overrideWithValue('run-1'),
        ],
      );
      addTearDown(container.dispose);

      container.read(endExpired)();

      expect(
        container.read(sessionExpiredNoticeProvider),
        contains('위치 전송이 멈췄습니다'),
      );
    });
  });

  group('로그인 화면', () {
    Future<void> pumpLogin(WidgetTester tester, {String? notice}) =>
        tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionExpiredNoticeProvider.overrideWith((ref) => notice),
            ],
            child: const MaterialApp(home: LoginScreen()),
          ),
        );

    testWidgets('만료로 돌아왔으면 안내를 보여준다', (tester) async {
      await pumpLogin(tester, notice: '로그인이 만료됐습니다. 다시 로그인해 주세요');

      expect(find.text('로그인이 만료됐습니다. 다시 로그인해 주세요'), findsOneWidget);
    });

    testWidgets('처음 열었거나 직접 로그아웃했으면 안내가 없다', (tester) async {
      await pumpLogin(tester);

      expect(find.textContaining('만료'), findsNothing);
    });
  });
}
