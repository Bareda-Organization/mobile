import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/features/auth/presentation/login_screen.dart';

/// R48 로그인(시안 `login` · `--error`) — 브랜드 줄 `학부모 · 학생`(P4) · 입력 칸 라벨에 `*` 없음 ·
/// 잔여 시도가 적으면 잠금 경고.
class _FailingLoginRepository implements AuthRepository {
  new(this.remaining);

  final int remaining;

  @override
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  }) => Future.error(
    Failure.api(
      statusCode: 401,
      code: 'INVALID_CREDENTIALS',
      message: '아이디 또는 비밀번호가 올바르지 않습니다',
      details: {'remaining_attempts': remaining},
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _pump(WidgetTester tester, {AuthRepository? repository}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repository != null)
          authRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: LoginScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('브랜드 줄에 이 앱을 쓰는 사람이 적혀 있다 — 학부모 · 학생(P4)', (tester) async {
    await _pump(tester);

    expect(find.text('바래다'), findsOneWidget);
    expect(find.text('학부모 · 학생'), findsOneWidget);
    expect(find.textContaining('지금 어디쯤인지 한눈에 봐요'), findsOneWidget);
  });

  testWidgets('입력 칸 라벨에 빨간 별표가 없다 — 둘 다 필수라 표시하지 않는다', (tester) async {
    await _pump(tester);

    for (final input in tester.widgetList<BaraedaInput>(
      find.byType(BaraedaInput),
    )) {
      expect(input.required, isFalse);
    }
    expect(find.text('로그인'), findsOneWidget);
    expect(find.text('처음이세요? 회원가입'), findsOneWidget);
  });

  testWidgets('잔여 시도가 2회 이하이면 "N번 더 틀리면 계정이 잠겨요" 경고가 나온다', (tester) async {
    await _pump(tester, repository: _FailingLoginRepository(2));
    await tester.enterText(find.byType(TextField).first, 'parentA1');
    await tester.enterText(find.byType(TextField).at(1), 'wrong');
    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();

    expect(find.text('2번 더 틀리면 계정이 잠겨요'), findsOneWidget);
    expect(find.text('잠기면 직접 풀 수 없고 학원에 문의해야 해요'), findsOneWidget);
  });

  testWidgets('잔여 시도가 넉넉하면 잠금 경고는 없다', (tester) async {
    await _pump(tester, repository: _FailingLoginRepository(4));
    await tester.enterText(find.byType(TextField).first, 'parentA1');
    await tester.enterText(find.byType(TextField).at(1), 'wrong');
    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();

    expect(find.textContaining('계정이 잠겨요'), findsNothing);
  });

  // 시안 `login` 의 `비밀번호 보기` — 입력한 비밀번호가 맞는지 눈으로 확인할 수 있어야 틀려서 잠기는 일이 준다.
  testWidgets('비밀번호는 가려지고, 보기 단추를 누르면 보이며 다시 누르면 가려진다', (tester) async {
    await _pump(tester);
    // 입력 칸은 아이디 · 비밀번호 순이다(라벨은 RichText 라 글자로 못 찾는다).
    final password = find.byType(BaraedaInput).at(1);
    bool obscured() => tester.widget<BaraedaInput>(password).obscureText;

    expect(obscured(), isTrue);

    await tester.tap(find.bySemanticsLabel('비밀번호 보기'));
    await tester.pump();
    expect(obscured(), isFalse);

    await tester.tap(find.bySemanticsLabel('비밀번호 가리기'));
    await tester.pump();
    expect(obscured(), isTrue);
  });
}
