// 가려진 입력(비밀번호)의 보기 전환(Ruling 834 · 시안 `password` `login`) —
// 눈 아이콘을 누르면 보이고 다시 누르면 가려진다. 두 앱의 비밀번호 칸이 따로 손대지 않아도 갖는다.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: BaraedaTheme.light(),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

bool _obscured(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).obscureText;

void main() {
  testWidgets('가려진 칸은 처음에 가려져 있고 눈 아이콘을 누르면 보이며 다시 누르면 가려진다', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(const BaraedaInput(label: '비밀번호', obscureText: true)),
    );
    expect(_obscured(tester), isTrue);

    await tester.tap(find.bySemanticsLabel('비밀번호 보기'));
    await tester.pump();
    expect(_obscured(tester), isFalse);

    await tester.tap(find.bySemanticsLabel('비밀번호 숨기기'));
    await tester.pump();
    expect(_obscured(tester), isTrue);
    handle.dispose();
  });

  testWidgets('낭독 이름은 가려진 동안 `비밀번호 보기` 이고 보이는 동안 `비밀번호 숨기기` 다', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(const BaraedaInput(label: '비밀번호', obscureText: true)),
    );
    expect(find.bySemanticsLabel('비밀번호 보기'), findsOneWidget);
    expect(find.bySemanticsLabel('비밀번호 숨기기'), findsNothing);

    await tester.tap(find.bySemanticsLabel('비밀번호 보기'));
    await tester.pump();
    expect(find.bySemanticsLabel('비밀번호 숨기기'), findsOneWidget);
    expect(find.bySemanticsLabel('비밀번호 보기'), findsNothing);
    handle.dispose();
  });

  testWidgets('눈 아이콘의 누름 영역은 44 이상이다', (tester) async {
    await tester.pumpWidget(
      _host(const BaraedaInput(label: '비밀번호', obscureText: true)),
    );

    final size = tester.getSize(find.byType(BaraedaIconButton));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('가렸다 보였다 해도 입력한 글자는 그대로다', (tester) async {
    final controller = TextEditingController(text: 'secret-1');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        BaraedaInput(label: '비밀번호', obscureText: true, controller: controller),
      ),
    );

    await tester.tap(find.byType(BaraedaIconButton));
    await tester.pump();
    expect(controller.text, 'secret-1');
  });

  testWidgets('가려지지 않는 칸에는 눈 아이콘이 없다', (tester) async {
    await tester.pumpWidget(_host(const BaraedaInput(label: '아이디')));

    expect(find.byType(BaraedaIconButton), findsNothing);
  });

  testWidgets('칸이 따로 준 suffix 가 있으면 그것을 쓰고 눈 아이콘을 덧붙이지 않는다', (tester) async {
    await tester.pumpWidget(
      _host(
        const BaraedaInput(
          label: '비밀번호',
          obscureText: true,
          suffix: Text('단위'),
        ),
      ),
    );

    expect(find.text('단위'), findsOneWidget);
    expect(find.byType(BaraedaIconButton), findsNothing);
  });

  testWidgets('같은 화면의 두 칸은 따로 바뀐다', (tester) async {
    await tester.pumpWidget(
      _host(
        const Column(
          children: [
            BaraedaInput(label: '현재 비밀번호', obscureText: true),
            BaraedaInput(label: '새 비밀번호', obscureText: true),
          ],
        ),
      ),
    );
    bool obscuredAt(int i) =>
        tester.widget<TextField>(find.byType(TextField).at(i)).obscureText;

    await tester.tap(find.byType(BaraedaIconButton).first);
    await tester.pump();

    expect(obscuredAt(0), isFalse);
    expect(obscuredAt(1), isTrue);
  });
}
