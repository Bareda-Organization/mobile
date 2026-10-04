// 읽기 전용 코드 표시 — 칸마다 한 글자, 만료되면 취소선이 그어지고 낭독도 만료를 말한다.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: BaraedaTheme.light(),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

void main() {
  testWidgets('코드 글자를 칸마다 하나씩 그린다', (tester) async {
    await tester.pumpWidget(_host(const BaraedaCodeDisplay(code: '614308')));

    for (final char in '614308'.split('')) {
      expect(find.text(char), findsWidgets);
    }
    expect(
      tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList(),
      ['6', '1', '4', '3', '0', '8'],
    );
  });

  testWidgets('만료되면 모든 글자에 취소선이 그어진다 — 살아 있는 코드에는 없다', (tester) async {
    await tester.pumpWidget(_host(const BaraedaCodeDisplay(code: '614308')));
    expect(
      tester
          .widgetList<Text>(find.byType(Text))
          .every((t) => t.style?.decoration == null),
      isTrue,
    );

    await tester.pumpWidget(
      _host(const BaraedaCodeDisplay(code: '614308', expired: true)),
    );
    expect(
      tester
          .widgetList<Text>(find.byType(Text))
          .every((t) => t.style?.decoration == TextDecoration.lineThrough),
      isTrue,
    );
  });

  testWidgets('낭독은 코드를 한 글자씩 끊어 읽고 만료를 말한다', (tester) async {
    await tester.pumpWidget(
      _host(const BaraedaCodeDisplay(code: '614308', expired: true)),
    );

    expect(find.bySemanticsLabel('만료된 연결 코드 6 1 4 3 0 8'), findsOneWidget);
  });
}
