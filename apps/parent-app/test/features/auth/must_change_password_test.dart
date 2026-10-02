import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/app.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/features/auth/presentation/login_screen.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';
import 'package:parent_app/features/settings/presentation/password_change_screen.dart';

import '../../support/fake_token_storage.dart';

/// Ruling 540 · R46-LAST `Ruling 581` — 관리자가 초기화한 임시 비밀번호로 들어온
/// 학부모·학생 계정은 비밀번호를 바꾸기 전까지 다른 화면을 쓰지 못한다. 서버도
/// 그동안 다른 API 를 `403 PASSWORD_CHANGE_REQUIRED` 로 막으므로 앱은 변경 화면에
/// 고정한다(매니저 앱 `must_change_password_test.dart` 와 같은 갈래).
class _FakeAuthRepository implements AuthRepository {
  new({
    required this.mustChangePassword,
    this.role = AccountRole.parent,
  });

  final bool mustChangePassword;
  final AccountRole role;
  int logoutCalls = 0;
  int changePasswordCalls = 0;

  @override
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  }) async => LoginResponse(
    accessToken: 'access',
    refreshToken: 'refresh',
    role: role,
    status: AccountStatus.active,
    accountId: '7',
    mustChangePassword: mustChangePassword,
  );

  @override
  Future<MeResponse> me() async => MeResponse(
    accountId: '7',
    loginId: 'parentA1',
    name: '학부모',
    phone: '010-0000-0000',
    role: role,
    status: AccountStatus.active,
    mustChangePassword: mustChangePassword,
  );

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async => changePasswordCalls++;

  @override
  Future<void> logout() async => logoutCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Widget _app(
  _FakeAuthRepository repository, {
  FakeTokenStorage? tokenStorage,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    tokenStorageProvider.overrideWithValue(tokenStorage ?? FakeTokenStorage()),
    authRepositoryProvider.overrideWithValue(repository),
    ...overrides,
  ],
  child: const BaraedaParentApp(),
);

Future<void> _loginAs(WidgetTester tester, String password) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), 'parentA1');
  await tester.enterText(fields.at(1), password);
  await tester.tap(find.widgetWithText(BaraedaButton, '로그인하기'));
  await tester.pumpAndSettle();
}

void main() {
  for (final role in [AccountRole.parent, AccountRole.student]) {
    testWidgets('${role.wireValue} — 로그인 응답의 표식이 켜져 있으면 홈이 아니라 변경 화면으로 간다', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(_FakeAuthRepository(mustChangePassword: true, role: role)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      await _loginAs(tester, 'temp-pass');

      expect(find.byType(PasswordChangeScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });
  }

  testWidgets('표식이 없는 로그인은 그대로 홈으로 간다', (tester) async {
    await tester.pumpWidget(
      _app(_FakeAuthRepository(mustChangePassword: false)),
    );
    await tester.pumpAndSettle();

    await _loginAs(tester, 'password');

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(PasswordChangeScreen), findsNothing);
  });

  testWidgets('자동 로그인(/me)의 표식이 켜져 있어도 변경 화면에 고정된다', (tester) async {
    await tester.pumpWidget(
      _app(
        _FakeAuthRepository(mustChangePassword: true),
        tokenStorage: FakeTokenStorage(seedRefreshToken: 'refresh'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PasswordChangeScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('강제 변경 화면은 뒤로 갈 길이 없고 안내와 로그아웃만 있다', (tester) async {
    final repository = _FakeAuthRepository(mustChangePassword: true);
    await tester.pumpWidget(
      _app(
        repository,
        overrides: [
          currentUserRoleProvider.overrideWith((ref) => UserRole.parent),
          currentAccountStatusProvider.overrideWith(
            (ref) => AccountStatus.active,
          ),
          mustChangePasswordProvider.overrideWith((ref) => true),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PasswordChangeScreen), findsOneWidget);
    expect(find.byTooltip('뒤로'), findsNothing);
    expect(find.textContaining('관리자가 초기화한 임시 비밀번호'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '로그아웃'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BaraedaButton, '로그아웃하기'));
    await tester.pumpAndSettle();

    expect(repository.logoutCalls, 1);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('비밀번호를 바꾸면 표식이 풀려 다음 로그인은 홈으로 간다', (tester) async {
    final repository = _FakeAuthRepository(mustChangePassword: true);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await _loginAs(tester, 'temp-pass');
    expect(find.byType(PasswordChangeScreen), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'temp-pass');
    await tester.enterText(fields.at(1), 'new-password-1');
    await tester.tap(find.widgetWithText(BaraedaButton, '변경하기'));
    await tester.pumpAndSettle();

    expect(repository.changePasswordCalls, 1);
    expect(find.byType(LoginScreen), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LoginScreen)),
    );
    expect(container.read(mustChangePasswordProvider), isFalse);
  });
}
