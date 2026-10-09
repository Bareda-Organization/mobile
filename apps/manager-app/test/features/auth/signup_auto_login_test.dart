import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/academy_contact_store.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/auth/presentation/signup_screen.dart';

import '../../support/fake_academy_contact_store.dart';

/// 861 ⑥ · L2(UF-X-01) — 가입이 접수되면 곧바로 로그인해 승인 대기 화면으로 간다(학부모 앱과 같은 동작).
/// 로그인이 실패해도 가입은 접수됐으니 "가입 실패" 로 보이지 않고 로그인 화면으로 돌려보낸다.
const _academy = AcademySummary(
  id: 'a1',
  name: '하늘수학학원 부천중동점',
  region: '경기 부천시 원미구',
  code: 'HN-0012',
);

class _FakeAuthRepository implements AuthRepository {
  new({required this.loginSucceeds});

  final bool loginSucceeds;
  final calls = <String>[];

  @override
  Future<List<AcademySummary>> searchAcademies(String query) async => [
    _academy,
  ];

  @override
  Future<SignupResponse> signup(SignupRequest request) async {
    calls.add('signup');
    return SignupResponse(
      accountStatus: 'pending',
      requestedAt: DateTime(2026, 10, 10, 9),
      approver: 'staff',
    );
  }

  @override
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  }) async {
    calls.add('login:$loginId');
    // Failure 는 Exception/Error 를 상속하지 않는다(다른 시험의 같은 패턴).
    // ignore: only_throw_errors
    if (!loginSucceeds) throw const Failure.network();
    return const LoginResponse(
      accessToken: 'access',
      refreshToken: 'refresh',
      role: AccountRole.driver,
      status: AccountStatus.pending,
      accountId: '7',
      academy: AcademyRef(id: 'a1', name: '하늘수학학원', contact: '032-000-1100'),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late ProviderContainer container;
  late FakeAcademyContactStore contactStore;

  Future<_FakeAuthRepository> submit(
    WidgetTester tester, {
    required bool loginSucceeds,
  }) async {
    final repository = _FakeAuthRepository(loginSucceeds: loginSucceeds);
    contactStore = FakeAcademyContactStore();
    final router = GoRouter(
      initialLocation: AppRoutes.signup,
      routes: [
        GoRoute(
          path: AppRoutes.signup,
          builder: (_, _) => const SignupScreen(),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (_, _) => const Text('LOGIN_MARKER'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          academyContactStoreProvider.overrideWithValue(contactStore),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(SignupScreen)),
    );
    Future<void> type(int field, String text) async {
      await tester.enterText(find.byType(TextField).at(field), text);
      await tester.pump();
    }

    await type(0, 'driverA2');
    await type(1, 'password');
    await type(2, '박정훈');
    await type(3, '010-4821-7730');
    await type(4, '하늘');
    await tester.ensureVisible(find.text('검색하기'));
    await tester.tap(find.text('검색하기'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_academy.displayLabel).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(BaraedaButton, '가입 신청하기'));
    await tester.tap(find.widgetWithText(BaraedaButton, '가입 신청하기'));
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('가입이 접수되면 곧바로 로그인해 승인 대기 상태가 된다', (tester) async {
    final repository = await submit(tester, loginSucceeds: true);

    expect(repository.calls, ['signup', 'login:driverA2']);
    expect(container.read(currentUserRoleProvider), UserRole.driver);
    expect(container.read(currentAccountStatusProvider), AccountStatus.pending);
    expect(find.text('LOGIN_MARKER'), findsNothing);
  });

  // 승인 대기 중에 관리자가 계정을 막으면 로그인 응답을 다시 받을 길이 없다 —
  // 가입 직후 로그인도 연락처를 남겨야 한다(Ruling 825).
  testWidgets('가입 직후 로그인도 학원 연락처를 들고 있고 기기에 남긴다', (tester) async {
    await submit(tester, loginSucceeds: true);

    expect(container.read(academyContactProvider), '032-000-1100');
    expect(await contactStore.read(), '032-000-1100');
  });

  testWidgets('로그인이 실패하면 가입 실패가 아니라 로그인 화면으로 돌려보낸다', (tester) async {
    await submit(tester, loginSucceeds: false);

    expect(container.read(currentUserRoleProvider), isNull);
    expect(find.text('LOGIN_MARKER'), findsOneWidget);
    expect(find.textContaining('가입 신청에 실패'), findsNothing);
  });
}
