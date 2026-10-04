import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/me_provider.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/auth/presentation/password_change_screen.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/home/presentation/me_screen.dart';

/// R32 M13 — 매니저 앱에는 비밀번호를 바꿀 길이 없었다(AUTH-07 · UF-X-09 — 전 역할). 학부모 앱
/// 화면을 본보기로 만들었다. 성공하면 서버가 refresh 토큰을 전량 무효화하므로 이 기기도
/// 로그아웃해 다시 로그인하게 한다.
class _RecordingAuthRepository implements AuthRepository {
  new({this.failure});

  final Failure? failure;
  final changes = <({String current, String next})>[];
  int logoutCalls = 0;

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changes.add((current: currentPassword, next: newPassword));
    // Failure 는 Exception/Error 를 상속하지 않는다(다른 시험의 같은 패턴).
    // ignore: only_throw_errors
    if (failure != null) throw failure!;
  }

  @override
  Future<void> logout() async => logoutCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  Future<ProviderContainer> pumpScreen(
    WidgetTester tester,
    _RecordingAuthRepository repository,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: PasswordChangeScreen()),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PasswordChangeScreen)),
    );
    container.read(currentUserRoleProvider.notifier).state = UserRole.driver;
    container.read(currentAccountStatusProvider.notifier).state =
        AccountStatus.active;
    return container;
  }

  Future<void> fillAndSubmit(
    WidgetTester tester, {
    String current = 'old-pass',
    String next = 'new-pass-1',
  }) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), current);
    await tester.enterText(fields.at(1), next);
    // 단추가 입력에 따라 켜지므로(M15) 다시 그린 뒤에 누른다.
    await tester.pump();
    await tester.tap(find.widgetWithText(BaraedaButton, '변경하기'));
    await tester.pumpAndSettle();
  }

  testWidgets('성공하면 서버에 바꾸고, 이 기기도 로그아웃해 다시 로그인하게 한다', (tester) async {
    final repository = _RecordingAuthRepository();
    final container = await pumpScreen(tester, repository);

    await fillAndSubmit(tester);

    expect(repository.changes, [(current: 'old-pass', next: 'new-pass-1')]);
    expect(repository.logoutCalls, 1);
    expect(container.read(currentUserRoleProvider), isNull);
  });

  testWidgets('현재 비밀번호가 틀리면 그 칸에 알리고 로그아웃하지 않는다', (tester) async {
    final repository = _RecordingAuthRepository(
      failure: const ApiFailure(
        code: 'INVALID_CREDENTIALS',
        message: '원문',
        statusCode: 401,
      ),
    );
    final container = await pumpScreen(tester, repository);

    await fillAndSubmit(tester);

    expect(find.text('현재 비밀번호가 올바르지 않습니다'), findsOneWidget);
    expect(repository.logoutCalls, 0);
    expect(container.read(currentUserRoleProvider), UserRole.driver);
  });

  testWidgets('통신이 끊기면 쉬운 문구로 알리고 로그아웃하지 않는다', (tester) async {
    final repository = _RecordingAuthRepository(
      failure: const NetworkFailure(),
    );
    await pumpScreen(tester, repository);

    await fillAndSubmit(tester);

    expect(find.text('네트워크 상태를 확인해 주세요'), findsOneWidget);
    expect(repository.logoutCalls, 0);
  });

  testWidgets('빈 칸이 있으면 요청을 보내지 않는다', (tester) async {
    final repository = _RecordingAuthRepository();
    await pumpScreen(tester, repository);

    await fillAndSubmit(tester, next: '');

    expect(repository.changes, isEmpty);
  });

  BaraedaButton changeButton(WidgetTester tester) =>
      tester.widget<BaraedaButton>(find.widgetWithText(BaraedaButton, '변경하기'));

  // M15 — 꺼진 단추는 왜 꺼졌는지 단추 아래에 적는다.
  testWidgets('새 비밀번호가 비어 있으면 [변경하기] 가 꺼지고 이유가 단추 아래에 보인다(M15)', (
    tester,
  ) async {
    await pumpScreen(tester, _RecordingAuthRepository());

    await tester.enterText(find.byType(TextField).at(0), 'old-pass');
    await tester.pump();

    expect(changeButton(tester).onPressed, isNull);
    expect(find.text('새 비밀번호를 입력하면 눌러요'), findsOneWidget);
  });

  testWidgets('현재 비밀번호가 비어 있으면 그것을 이유로 알린다', (tester) async {
    await pumpScreen(tester, _RecordingAuthRepository());

    await tester.enterText(find.byType(TextField).at(1), 'new-pass-1');
    await tester.pump();

    expect(changeButton(tester).onPressed, isNull);
    expect(find.text('현재 비밀번호를 입력하면 눌러요'), findsOneWidget);
  });

  testWidgets('두 칸이 다 차면 [변경하기] 가 켜지고 이유 글이 사라진다', (tester) async {
    await pumpScreen(tester, _RecordingAuthRepository());

    await tester.enterText(find.byType(TextField).at(0), 'old-pass');
    await tester.enterText(find.byType(TextField).at(1), 'new-pass-1');
    await tester.pump();

    expect(changeButton(tester).onPressed, isNotNull);
    expect(find.textContaining('입력하면 눌러요'), findsNothing);
  });

  // M14 — 서버는 UTF-8 72바이트(한글 24자)를 넘으면 422 로 거절한다. 입력할 때 미리 알린다.
  testWidgets('새 비밀번호 칸에 한도 안내가 있고 넘으면 이유를 보이며 단추가 꺼진다(M14)', (tester) async {
    final repository = _RecordingAuthRepository();
    await pumpScreen(tester, repository);
    expect(find.text('영문 72자 · 한글 24자까지'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'old-pass');
    await tester.enterText(find.byType(TextField).at(1), '가' * 25); // 75바이트
    await tester.pump();

    expect(find.text('비밀번호는 72바이트(한글 24자) 이하여야 해요'), findsOneWidget);
    expect(changeButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField).at(1), '가' * 24); // 72바이트
    await tester.pump();

    expect(find.textContaining('이하여야 해요'), findsNothing);
    expect(changeButton(tester).onPressed, isNotNull);
  });

  testWidgets('내 정보의 [비밀번호 변경] 칸이 이 화면으로 간다', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const MeScreen()),
        GoRoute(
          path: AppRoutes.passwordChange,
          builder: (_, _) => const Text('PASSWORD_CHANGE_MARKER'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayRunsProvider.overrideWith((ref) async => []),
          meProvider.overrideWith((ref) async => throw StateError('내 정보 미사용')),
          currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('비밀번호 변경'));
    await tester.pumpAndSettle();

    expect(find.text('PASSWORD_CHANGE_MARKER'), findsOneWidget);
  });
}
