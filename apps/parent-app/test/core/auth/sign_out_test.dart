import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/core/auth/user_role.dart';

/// 로그아웃만 쓰는 가짜 — 나머지 메서드는 이 시험에서 불리면 안 된다.
class _StubAuthRepository implements AuthRepository {
  new({this.fail = false});

  final bool fail;
  int logoutCalls = 0;

  @override
  Future<void> logout() async {
    logoutCalls++;
    if (fail) throw Exception('network down');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 로그아웃(2026-09-23 사용자 지시) — 역할이 비면 라우터가 로그인 화면으로 보낸다. 서버 호출이 실패해도
/// 이 기기에서는 로그아웃해야 한다 — 네트워크가 끊긴 기사가 다른 계정으로 바꿔 타지 못하면 안 된다.
void main() {
  late _StubAuthRepository repository;
  late WidgetRef capturedRef;

  Future<ProviderContainer> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox();
          },
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SizedBox)),
    );
    container.read(currentUserRoleProvider.notifier).state =
        UserRole.values.first;
    container.read(currentAccountStatusProvider.notifier).state =
        AccountStatus.active;
    return container;
  }

  testWidgets('서버에 알리고 역할·상태를 비운다', (tester) async {
    repository = _StubAuthRepository();
    final container = await pump(tester);

    await signOut(capturedRef);

    expect(repository.logoutCalls, 1);
    expect(container.read(currentUserRoleProvider), isNull);
    expect(container.read(currentAccountStatusProvider), isNull);
  });

  testWidgets('서버 호출이 실패해도 이 기기에서는 로그아웃한다', (tester) async {
    repository = _StubAuthRepository(fail: true);
    final container = await pump(tester);

    await expectLater(signOut(capturedRef), throwsException);

    expect(container.read(currentUserRoleProvider), isNull);
  });
}
