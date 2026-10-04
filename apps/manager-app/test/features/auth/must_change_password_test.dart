import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/app.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/auth/presentation/login_screen.dart';
import 'package:manager_app/features/auth/presentation/password_change_screen.dart';
import 'package:manager_app/features/home/presentation/home_screen.dart';

import '../../support/fake_token_storage.dart';

/// Ruling 540 — 관리자가 초기화한 임시 비밀번호로 들어온 계정은 비밀번호를 바꾸기 전까지 다른 화면을 쓰지
/// 못한다. 서버도 그동안 다른 API 를 `403 PASSWORD_CHANGE_REQUIRED` 로 막으므로 앱은 변경 화면으로 보낸다.
class _FakeAuthRepository implements AuthRepository {
  new({required this.mustChangePassword});

  final bool mustChangePassword;
  int logoutCalls = 0;

  @override
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  }) async => LoginResponse(
    accessToken: 'access',
    refreshToken: 'refresh',
    role: AccountRole.driver,
    status: AccountStatus.active,
    accountId: '7',
    mustChangePassword: mustChangePassword,
  );

  @override
  Future<void> logout() async => logoutCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('로그인 응답의 표식이 켜져 있으면 홈이 아니라 비밀번호 변경 화면으로 간다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(mustChangePassword: true),
          ),
        ],
        child: const BaraedaManagerApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'driverA1');
    await tester.enterText(fields.at(1), 'temp-pass');
    await tester.tap(find.widgetWithText(BaraedaButton, '로그인'));
    await tester.pumpAndSettle();

    expect(find.byType(PasswordChangeScreen), findsOneWidget);
    expect(find.byType(ManagerHomeScreen), findsNothing);
  });

  testWidgets('표식이 없는 로그인은 그대로 홈으로 간다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(mustChangePassword: false),
          ),
        ],
        child: const BaraedaManagerApp(),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'driverA1');
    await tester.enterText(fields.at(1), 'password');
    await tester.tap(find.widgetWithText(BaraedaButton, '로그인'));
    await tester.pumpAndSettle();

    expect(find.byType(ManagerHomeScreen), findsOneWidget);
    expect(find.byType(PasswordChangeScreen), findsNothing);
  });

  testWidgets('강제 변경 화면은 뒤로 갈 길이 없고 로그아웃만 열려 있다', (tester) async {
    final repository = _FakeAuthRepository(mustChangePassword: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          authRepositoryProvider.overrideWithValue(repository),
          currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
          currentAccountStatusProvider.overrideWith(
            (ref) => AccountStatus.active,
          ),
          mustChangePasswordProvider.overrideWith((ref) => true),
        ],
        child: const BaraedaManagerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PasswordChangeScreen), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.textContaining('관리자가 초기화한 임시 비밀번호'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '로그아웃'));
    await tester.pumpAndSettle();

    expect(repository.logoutCalls, 1);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
