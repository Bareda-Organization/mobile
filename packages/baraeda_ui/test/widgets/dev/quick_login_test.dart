// [QuickLogin] 시험 — 배포 시험 빌드에서만 켜지는 단추라 "값이 없으면 아무것도 안 그린다"가 요점이다.
//
// ⚠ 시험 값은 가짜다. 실제 비밀번호는 소스·시험 어디에도 두지 않는다(Ruling 877).
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: BaraedaTheme.light(),
    home: Scaffold(body: child),
  );

  const accounts = [QuickLoginAccount('학부모', 'parentA1')];

  testWidgets('비밀번호 값이 비어 있으면 단추를 하나도 그리지 않는다', (tester) async {
    await tester.pumpWidget(
      // password 를 안 넘기면 기본값(빌드 때 준 값)이고, 시험은 그 값을 주지 않고 돈다.
      wrap(QuickLogin(accounts: accounts, onPick: (_, _) {})),
    );

    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.text('학부모 · parentA1'), findsNothing);
  });

  testWidgets('값이 있으면 단추를 그리고, 누르면 아이디와 그 값을 함께 넘긴다', (tester) async {
    final picked = <List<String>>[];
    await tester.pumpWidget(
      wrap(
        QuickLogin(
          accounts: accounts,
          password: 'fake-pw',
          onPick: (id, pw) => picked.add([id, pw]),
        ),
      ),
    );

    expect(find.text('학부모 · parentA1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quick-login-parentA1')));
    await tester.pump();

    expect(picked, [
      ['parentA1', 'fake-pw'],
    ]);
  });
}
