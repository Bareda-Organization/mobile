// `BaraedaButton.sm` — 보이는 크기는 36 으로 두고 누르는 영역만 48 이상으로 넓힌다(F07-10 · Ruling 404).
// 이웃 버튼과 누르는 영역이 겹치면 오조작이므로 그것도 함께 고정한다.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: BaraedaTheme.light(),
      home: Scaffold(body: Center(child: child)),
    ),
  );

  BaraedaButton sm(String label, VoidCallback onPressed) => BaraedaButton(
    label: label,
    size: BaraedaButtonSize.sm,
    onPressed: onPressed,
  );

  testWidgets('sm 버튼의 누르는 영역은 48×48 이상이다', (tester) async {
    await pump(tester, sm('가', () {}));
    final size = tester.getSize(find.byType(BaraedaButton));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
  });

  testWidgets('sm 버튼의 보이는 크기는 36 그대로다', (tester) async {
    await pump(tester, sm('확인', () {}));
    expect(tester.getSize(find.byType(Ink)).height, 36);
  });

  testWidgets('보이는 윗변보다 위 · 아랫변보다 아래를 눌러도 눌린다(누르는 영역 안)', (tester) async {
    var pressed = 0;
    await pump(tester, sm('확인', () => pressed++));
    final visual = tester.getRect(find.byType(Ink));
    await tester.tapAt(visual.topCenter - const Offset(0, 5));
    await tester.tapAt(visual.bottomCenter + const Offset(0, 5));
    expect(pressed, 2);
  });

  testWidgets('누르는 영역 밖은 눌리지 않는다', (tester) async {
    var pressed = 0;
    await pump(tester, sm('확인', () => pressed++));
    final visual = tester.getRect(find.byType(Ink));
    await tester.tapAt(visual.topCenter - const Offset(0, 30));
    expect(pressed, 0);
  });

  testWidgets('이웃한 sm 버튼끼리 누르는 영역이 겹치지 않는다', (tester) async {
    final taps = <String>[];
    await pump(
      tester,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          sm('탑승', () => taps.add('탑승')),
          sm('미승차', () => taps.add('미승차')),
        ],
      ),
    );
    final a = tester.getRect(find.widgetWithText(BaraedaButton, '탑승'));
    final b = tester.getRect(find.widgetWithText(BaraedaButton, '미승차'));
    expect(a.right, lessThanOrEqualTo(b.left));

    // 경계 양쪽 한 칸씩 — 각자의 영역만 반응한다.
    await tester.tapAt(Offset(a.right - 1, a.center.dy));
    await tester.tapAt(Offset(b.left + 1, b.center.dy));
    expect(taps, ['탑승', '미승차']);
  });

  testWidgets('비활성 sm 버튼은 넓어진 영역을 눌러도 동작하지 않는다', (tester) async {
    await pump(
      tester,
      const BaraedaButton(label: '확인', size: BaraedaButtonSize.sm),
    );
    final visual = tester.getRect(find.byType(Ink));
    await tester.tapAt(visual.topCenter - const Offset(0, 5)); // 던지지 않으면 통과
    expect(tester.takeException(), isNull);
  });

  testWidgets('md·lg 는 그대로 48·52 이다', (tester) async {
    await pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BaraedaButton(label: 'md', onPressed: () {}),
          BaraedaButton(
            label: 'lg',
            size: BaraedaButtonSize.lg,
            onPressed: () {},
          ),
        ],
      ),
    );
    expect(tester.getSize(find.widgetWithText(BaraedaButton, 'md')).height, 48);
    expect(tester.getSize(find.widgetWithText(BaraedaButton, 'lg')).height, 52);
  });
}
