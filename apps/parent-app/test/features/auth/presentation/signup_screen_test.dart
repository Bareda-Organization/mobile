import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/core/ui/sticky_action_bar.dart';
import 'package:parent_app/features/auth/presentation/signup_screen.dart';

class _Repository implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<List<Never>>.value(const []);
}

/// F05-11 — API_SPEC §2.2 `login_id` 50자 이하 · `password` UTF-8 72바이트 이하.
/// 서버 422 문구를 기다리지 않고 입력란 옆에 이유를 보인다.
void main() {
  Future<void> pumpSignup(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(_Repository())],
        child: const MaterialApp(home: SignupScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('비밀번호가 72바이트를 넘으면 그 입력란 옆에 이유를 보인다', (tester) async {
    await pumpSignup(tester);

    await tester.enterText(find.byType(TextField).at(1), '가' * 25);
    await tester.pump();

    expect(find.textContaining('72바이트'), findsOneWidget);
  });

  // Ruling 833 — 시안에는 별표가 없다. 눈에는 아무것도 없고 화면 낭독기만 "필수" 를 읽는다.
  testWidgets('아이디 · 비밀번호 · 이름 · 연락처는 낭독기가 "필수" 를 읽고 눈에는 별표가 없다', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpSignup(tester);

    for (final name in ['아이디', '비밀번호', '이름', '연락처']) {
      expect(find.bySemanticsLabel('$name 필수'), findsOneWidget, reason: name);
    }
    final asterisk = tester
        .widgetList<RichText>(find.byType(RichText))
        .any((w) => w.text.toPlainText().contains('*'));
    expect(asterisk, isFalse);
    handle.dispose();
  });

  testWidgets('아이디가 50자를 넘으면 그 입력란 옆에 이유를 보인다', (tester) async {
    await pumpSignup(tester);

    await tester.enterText(find.byType(TextField).at(0), 'a' * 51);
    await tester.pump();

    expect(find.textContaining('50자'), findsOneWidget);
  });

  testWidgets('한도 안의 입력에는 안내가 없다', (tester) async {
    await pumpSignup(tester);

    await tester.enterText(find.byType(TextField).at(0), 'a' * 50);
    await tester.enterText(find.byType(TextField).at(1), '가' * 24);
    await tester.pump();

    // 입력칸 아래 보조 설명(`50자 이하`)은 늘 보인다 — 한도를 넘었을 때의 오류 문장만 없어야 한다.
    expect(find.textContaining('72바이트'), findsNothing);
    expect(find.textContaining('50자 이하여야'), findsNothing);
  });

  // R48 시안 `signup` — 승인이 필요하다는 안내를 맨 위에(가입한 뒤에야 알게 되던 것), 주 단추는 맨 아래에 고정.
  testWidgets('승인 안내가 폼 맨 위에 있고 [가입 신청하기] 는 아래 고정 줄에 있다', (tester) async {
    await pumpSignup(tester);

    const notice = '가입을 신청하면 학원 관계자가 승인한 뒤에 쓸 수 있어요.';
    expect(find.text(notice), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(notice)).dy,
      lessThan(tester.getTopLeft(find.byType(TextField).first).dy),
      reason: '안내가 첫 입력칸보다 위에 있어야 가입 전에 읽힌다',
    );
    expect(
      find.ancestor(
        of: find.text('가입 신청하기'),
        matching: find.byType(StickyActionBar),
      ),
      findsOneWidget,
    );
  });
}
