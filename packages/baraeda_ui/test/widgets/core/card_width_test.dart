// `BaraedaCard` 폭 — 부모가 폭을 정해 주면(Column stretch) 상태 띠(accent)가
// 있어도 본체가 그 폭을 채운다(R46-SCREEN). accent 가 있을 때 본체를 Stack 에
// 넣어, 기본(loose)이면 자식 폭으로 줄어든 결함이 있었다.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parentWidth = 400.0;

  for (final accent in [null, BaraedaStatus.missed]) {
    testWidgets('accent=$accent 카드는 부모가 정한 폭을 채운다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BaraedaTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: parentWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BaraedaCard(accent: accent, child: const Text('짧은 글')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final body = find.descendant(
        of: find.byType(BaraedaCard),
        matching: find.byType(Container),
      );
      expect(tester.getSize(body.first).width, parentWidth);
    });
  }
}
