import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/auth/presentation/login_screen.dart';

/// 로그인 요청이 어떤 아이디·비밀번호로 나갔는지 기록하고 실패로 돌려보낸다.
class _RecordingLoginRepository implements AuthRepository {
  final calls = <List<String>>[];

  @override
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  }) {
    calls.add([loginId, password]);
    return Future.error(
      const Failure.api(
        statusCode: 401,
        code: 'INVALID_CREDENTIALS',
        message: '아이디 또는 비밀번호가 올바르지 않습니다',
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _pump(
  WidgetTester tester, {
  AuthRepository? repository,
  String? quickLoginPassword,
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repository != null)
          authRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        home: quickLoginPassword == null
            ? const LoginScreen()
            : LoginScreen(quickLoginPassword: quickLoginPassword),
      ),
    ),
  );
  await tester.pump();
}

/// M5(Ruling 329 · UF-X-04) — 매니저 앱(기사·동승자)은 학부모·학생과 같은
/// "학원 관계자 경유" 복구만 연다. 전화번호 복구 화면(SMS 연동 전 503)은
/// 만들지 않고, 로그인 화면에 안내 한 줄만 둔다(parent-app
/// `account_recovery_screen.dart` · 웹 `LoginForm.tsx` 와 같은 안내 방향).
void main() {
  testWidgets('로그인 화면에 학원 경유 비밀번호 초기화 안내가 보인다', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.pump();

    expect(find.textContaining('학원'), findsWidgets);
    expect(find.textContaining('초기화'), findsOneWidget);
  });

  // Ruling 877 — 배포 시험 빌드에서만 역할별 빠른 로그인 단추가 나온다
  // (--dart-define=QUICK_LOGIN_PASSWORD).
  testWidgets('QL 값이 있으면 기사 · 동승자 단추가 보이고, 누르면 그 아이디로 로그인 요청이 나간다', (
    tester,
  ) async {
    final repository = _RecordingLoginRepository();
    await _pump(tester, repository: repository, quickLoginPassword: 'fake-pw');

    expect(find.text('기사 · driverA3'), findsOneWidget);
    expect(find.text('동승자 · escortA3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('quick-login-driverA3')));
    await tester.pumpAndSettle();

    expect(repository.calls, [
      ['driverA3', 'fake-pw'],
    ]);
  });

  testWidgets('QL 값이 없으면 빠른 로그인 단추가 하나도 없다', (tester) async {
    await _pump(tester, quickLoginPassword: '');

    expect(find.byType(QuickLogin), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.text('driverA3'), findsNothing);
  });
}
