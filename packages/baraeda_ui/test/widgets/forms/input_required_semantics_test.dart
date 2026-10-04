// 필수 칸의 의미 정보(Ruling 833 · 시안엔 `*` 가 없다) — 눈에는 아무것도 덧붙이지 않고,
// 화면 낭독기만 칸 이름 뒤에 "필수" 를 읽는다.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: BaraedaTheme.light(),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

/// 라벨이 `RichText` 라 `find.text` 로는 못 찾는다 — 그려진 글자 전부에서 센다.
List<String> _drawnTexts(WidgetTester tester) => [
  for (final w in tester.widgetList<RichText>(find.byType(RichText)))
    w.text.toPlainText(),
];

bool _drawsAsterisk(WidgetTester tester) =>
    _drawnTexts(tester).any((t) => t.contains('*'));

void main() {
  testWidgets('필수 칸은 낭독기가 칸 이름 뒤에 "필수" 를 읽는다', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(const BaraedaInput(label: '이름', announceRequired: true)),
    );

    expect(find.bySemanticsLabel('이름 필수'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('필수 칸이어도 눈에는 별표가 없다', (tester) async {
    await tester.pumpWidget(
      _host(const BaraedaInput(label: '이름', announceRequired: true)),
    );

    expect(_drawnTexts(tester), contains('이름'));
    expect(_drawsAsterisk(tester), isFalse);
  });

  testWidgets('필수가 아닌 칸은 칸 이름만 읽는다', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const BaraedaInput(label: '이름')));

    expect(find.bySemanticsLabel('이름'), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('필수')), findsNothing);
    handle.dispose();
  });

  testWidgets('눈에 보이는 별표(required)는 그대로 별표를 그린다', (tester) async {
    await tester.pumpWidget(
      _host(const BaraedaInput(label: '이름', required: true)),
    );

    expect(_drawsAsterisk(tester), isTrue);
  });
}
