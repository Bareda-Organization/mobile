import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// R46 A — 오른쪽 컨트롤이 넓어도 이름 칸이 한 글자씩 세로로 쪼개지지 않는다.
void main() {
  Future<void> pumpRow(WidgetTester tester, double textScale) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: StudentRow(
            name: '김서준서준',
            meta: '3반 · 12:03:10 만료',
            actions: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              children: [
                BaraedaButton(
                  label: '연락 기록',
                  size: BaraedaButtonSize.sm,
                  onPressed: () {},
                ),
                BaraedaButton(
                  label: '되돌리기',
                  size: BaraedaButtonSize.sm,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  for (final scale in [1.0, 1.3]) {
    testWidgets('글자 배율 $scale — 이름은 한 줄로 남고 버튼이 다음 줄로 넘어간다', (tester) async {
      await pumpRow(tester, scale);

      final nameText = tester.widget<Text>(find.text('김서준서준'));
      final oneLine =
          nameText.style!.fontSize! * nameText.style!.height! * scale;
      expect(
        tester.getSize(find.text('김서준서준')).height,
        lessThan(oneLine * 1.5),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
