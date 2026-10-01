import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/features/auth/presentation/signup_screen.dart';

/// R46 B2 #20 — 가입이 접수되면 로그인 화면으로 돌려보내지 않고 바로 승인 대기로 들어간다.
/// 서버는 가입 응답(§2.2)에 토큰을 주지 않지만, `pending` 계정도 로그인은 성공한다(§2.5) —
/// 방금 입력한 자격으로 로그인해 라우터가 대기 화면으로 보내게 한다.
class _Repository implements AuthRepository {
  _Repository({this.loginFails = false});

  final bool loginFails;
  SignupRequest? signedUp;
  ({String loginId, String password})? loggedInWith;

  @override
  Future<List<AcademySummary>> searchAcademies(String query) async => const [
    AcademySummary(id: 'a-1', name: '바래다학원', region: '서울', code: 'A-001'),
  ];

  @override
  Future<SignupResponse> signup(SignupRequest request) async {
    signedUp = request;
    return SignupResponse(
      accountStatus: 'pending',
      requestedAt: DateTime(2026, 9, 12),
      approver: 'staff',
    );
  }

  @override
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  }) async {
    loggedInWith = (loginId: loginId, password: password);
    if (loginFails) return Future.error(const Failure.network());
    return const LoginResponse(
      accessToken: 't',
      role: AccountRole.parent,
      status: AccountStatus.pending,
      accountId: '1',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Repository repository,
) async {
  // 폼이 길어 기본 화면(800x600)에 안 담긴다 — 세로로 길게 열어 모든 칸을 한 번에 본다.
  tester.view
    ..physicalSize = const Size(800, 1800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: AppRoutes.signup,
    routes: [
      GoRoute(
        path: AppRoutes.signup,
        builder: (_, _) => const SignupScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, _) => const Scaffold(body: Text('로그인 화면')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(SignupScreen)),
    listen: false,
  );
}

Future<void> _fillAllButAcademy(WidgetTester tester) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), 'parent01');
  await tester.enterText(fields.at(1), 'secret-pw');
  await tester.enterText(fields.at(2), '김부모');
  await tester.enterText(fields.at(3), '010-1111-2222');
  await tester.pump();
}

Future<void> _pickAcademy(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(4), '바래다');
  await tester.tap(find.text('검색하기'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('바래다학원 · 서울 · A-001').last);
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  final button = find.text('가입 신청하기');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  group('B2 #20 가입 → 승인 대기', () {
    testWidgets('가입이 접수되면 방금 입력한 아이디·비밀번호로 로그인해 대기 계정이 된다', (tester) async {
      final repository = _Repository();
      final container = await _pump(tester, repository);
      await _fillAllButAcademy(tester);
      await _pickAcademy(tester);
      await _submit(tester);

      expect(repository.signedUp?.loginId, 'parent01');
      expect(repository.loggedInWith, (
        loginId: 'parent01',
        password: 'secret-pw',
      ));
      expect(
        container.read(currentAccountStatusProvider),
        AccountStatus.pending,
      );
      expect(container.read(currentUserRoleProvider), UserRole.parent);
      expect(find.text('로그인 화면'), findsNothing);
    });

    testWidgets('자동 로그인이 실패하면 예전처럼 로그인 화면으로 돌려보낸다', (tester) async {
      final repository = _Repository(loginFails: true);
      await _pump(tester, repository);
      await _fillAllButAcademy(tester);
      await _pickAcademy(tester);
      await _submit(tester);

      expect(repository.signedUp, isNotNull);
      expect(find.text('로그인 화면'), findsOneWidget);
    });
  });

  group('B2 #20 [가입 신청하기] 비활성 이유', () {
    testWidgets('빈 칸이 있으면 어느 항목이 비었는지 버튼 아래에 알린다', (tester) async {
      await _pump(tester, _Repository());
      await tester.enterText(find.byType(TextField).at(0), 'parent01');
      await tester.pump();

      final button = find.text('가입 신청하기');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(
        find.text('아직 채우지 않은 항목 · 비밀번호 · 이름 · 연락처 · 학원'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<BaraedaButton>(
              find.widgetWithText(BaraedaButton, '가입 신청하기'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('모두 채우면 안내가 사라지고 버튼이 켜진다', (tester) async {
      await _pump(tester, _Repository());
      await _fillAllButAcademy(tester);
      await _pickAcademy(tester);

      expect(find.textContaining('아직 채우지 않은 항목'), findsNothing);
      expect(
        tester
            .widget<BaraedaButton>(
              find.widgetWithText(BaraedaButton, '가입 신청하기'),
            )
            .onPressed,
        isNotNull,
      );
    });
  });
}
