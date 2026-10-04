// `BaraedaButton` 폭 — block 이 아니면 내용 폭, block 이면 부모 폭 전체(R43 · Ruling 406).
// 디자인 킷 Button.jsx 는 `display: block ? 'flex' : 'inline-flex'` 이다.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parentWidth = 400.0;

  // 부모가 폭 상한(400)을 주는 자리 — Column(가운데 정렬)과 Align 둘 다 자식에게 느슨한 폭을 준다.
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: BaraedaTheme.light(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: parentWidth, child: child),
        ),
      ),
    ),
  );

  for (final size in BaraedaButtonSize.values) {
    testWidgets('block 이 아닌 ${size.name} 버튼은 내용 폭이다(Column)', (tester) async {
      await pump(
        tester,
        Column(
          children: [BaraedaButton(label: '확인', size: size, onPressed: () {})],
        ),
      );
      expect(
        tester.getSize(find.byType(BaraedaButton)).width,
        lessThan(parentWidth),
      );
    });

    testWidgets('block 이 아닌 ${size.name} 버튼은 내용 폭이다(Align)', (tester) async {
      await pump(
        tester,
        Align(
          alignment: Alignment.centerLeft,
          child: BaraedaButton(label: '확인', size: size, onPressed: () {}),
        ),
      );
      expect(
        tester.getSize(find.byType(BaraedaButton)).width,
        lessThan(parentWidth),
      );
    });

    testWidgets('block 인 ${size.name} 버튼은 부모 폭 전체다', (tester) async {
      await pump(
        tester,
        Column(
          children: [
            BaraedaButton(
              label: '확인',
              size: size,
              block: true,
              onPressed: () {},
            ),
          ],
        ),
      );
      expect(tester.getSize(find.byType(BaraedaButton)).width, parentWidth);
    });
  }

  testWidgets('block 이 아닌 sm 버튼도 누르는 영역은 44 다', (tester) async {
    await pump(
      tester,
      Column(
        children: [
          BaraedaButton(
            label: '가',
            size: BaraedaButtonSize.sm,
            onPressed: () {},
          ),
        ],
      ),
    );
    final size = tester.getSize(find.byType(BaraedaButton));
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));
  });
}
