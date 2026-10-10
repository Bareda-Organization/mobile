import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/features/auth/presentation/login_screen.dart';

void main() {
  /// 세션 만료 처리를 provider 안에서 부르는 통로 — 함수가 `Ref` 를 받는다.
  final endExpired = Provider<void Function()>(
    (ref) =>
        () => endSessionAsExpired(ref),
  );

  // R51 — 재발급 거절은 다른 기기의 비밀번호 변경 · 차단으로도 생겨, 오래 쓰지 않은 탓이라고 단정하지 않는다.
  test('로그인이 풀리면 역할을 비우고 원인을 단정하지 않는 "로그인이 만료됐어요" 안내를 남긴다 (R46 · R51)', () {
    final container = ProviderContainer(
      overrides: [
        currentUserRoleProvider.overrideWith((ref) => UserRole.parent),
      ],
    );
    addTearDown(container.dispose);

    container.read(endExpired)();

    expect(container.read(currentUserRoleProvider), isNull);
    expect(
      container.read(sessionExpiredNoticeProvider),
      '로그인이 만료됐어요. 다시 로그인해 주세요.',
    );
  });

  testWidgets('만료로 돌아온 로그인 화면은 안내를 보여주고, 직접 열었을 때는 없다 (R46)', (tester) async {
    Future<void> pumpLogin(String? notice) => tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [sessionExpiredNoticeProvider.overrideWith((ref) => notice)],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await pumpLogin('로그인이 만료됐어요. 다시 로그인해 주세요.');
    // 제목과 본문에 같은 말이 두 번 나오지 않는다.
    expect(find.text('로그인이 만료됐어요. 다시 로그인해 주세요.'), findsOneWidget);
    expect(find.text('로그인이 만료됐어요'), findsNothing);

    await pumpLogin(null);
    expect(find.textContaining('로그인이 만료됐어요'), findsNothing);
  });
}
