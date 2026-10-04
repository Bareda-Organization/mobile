// 조작 요소 경계가 전용 토큰 `borderControl` 을 쓰는지 고정한다(F07-09 · Ruling 403).
// 카드 외곽선은 그대로 `borderDefault` 라는 것도 함께 — 값만 올려 전 화면이 진해지는 회귀를 막는다.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:baraeda_ui/widgets/forms/code_input_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final themes = <String, (ThemeData, BaraedaColors)>{
    '라이트': (BaraedaTheme.light(), BaraedaColors.light),
    '다크': (BaraedaTheme.dark(), BaraedaColors.dark),
  };

  for (final MapEntry(key: name, value: (theme, colors)) in themes.entries) {
    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(body: Center(child: child)),
      ),
    );

    Color enabledBorderColor(WidgetTester tester) {
      final decorator = tester.widget<InputDecorator>(
        find.byType(InputDecorator).first,
      );
      final border = decorator.decoration.enabledBorder! as OutlineInputBorder;
      return border.borderSide.color;
    }

    group(name, () {
      testWidgets('입력칸 테두리는 borderControl', (tester) async {
        await pump(tester, const BaraedaInput(label: '아이디'));
        expect(enabledBorderColor(tester), colors.borderControl);
      });

      testWidgets('여러 줄 입력칸 테두리는 borderControl', (tester) async {
        await pump(tester, const BaraedaTextarea(label: '메모'));
        expect(enabledBorderColor(tester), colors.borderControl);
      });

      testWidgets('선택칸 테두리는 borderControl', (tester) async {
        await pump(
          tester,
          BaraedaSelect(
            label: '회차',
            options: const [BaraedaSelectOption('a', label: 'A')],
            onChanged: (_) {},
          ),
        );
        expect(enabledBorderColor(tester), colors.borderControl);
      });

      // 시안은 꺼짐 트랙을 더 어두운 회색(`--c-end`)으로 둔다 — 이 시험이 지키던 것은
      // 색 이름이 아니라 "꺼짐 트랙이 인접 면과 3:1 이상" 이라는 조건(WCAG 1.4.11)이다.
      testWidgets('스위치 꺼짐 트랙은 shapeIdle 이고 카드 · 바탕과 3:1 이상이다', (tester) async {
        await pump(
          tester,
          BaraedaSwitch(checked: false, label: '알림', onChanged: (_) {}),
        );
        final track = tester
            .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.shape == BoxShape.rectangle);
        expect(track.color, colors.shapeIdle);
        double lum(Color c) => c.computeLuminance();
        double ratio(Color a, Color b) {
          final hi = lum(a) > lum(b) ? lum(a) : lum(b);
          final lo = lum(a) > lum(b) ? lum(b) : lum(a);
          return (hi + 0.05) / (lo + 0.05);
        }

        expect(
          ratio(track.color!, colors.surfaceCard),
          greaterThanOrEqualTo(3),
        );
        expect(ratio(track.color!, colors.bgBase), greaterThanOrEqualTo(3));
      });

      testWidgets('보조 버튼 윤곽은 borderControl', (tester) async {
        await pump(
          tester,
          BaraedaButton(
            label: '취소',
            variant: BaraedaButtonVariant.secondary,
            onPressed: () {},
          ),
        );
        final ink = tester.widget<Ink>(find.byType(Ink));
        final border = (ink.decoration! as BoxDecoration).border! as Border;
        expect(border.top.color, colors.borderControl);
      });

      testWidgets('지연 선택 칩(선택 전)은 borderControl', (tester) async {
        await pump(tester, DelayPicker(onChanged: (_) {}));
        final borders = tester
            .widgetList<Container>(find.byType(Container))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .map((d) => d.border)
            .whereType<Border>()
            .map((b) => b.top.color);
        expect(borders, contains(colors.borderControl));
      });

      testWidgets('코드 입력 칸(입력 전)은 borderControl', (tester) async {
        await pump(
          tester,
          const BaraedaCodeInputBox(char: '', active: false, hasError: false),
        );
        final box = tester.widget<Container>(find.byType(Container).first);
        final border = (box.decoration! as BoxDecoration).border! as Border;
        expect(border.top.color, colors.borderControl);
      });

      testWidgets('카드 외곽선은 borderDefault 를 그대로 쓴다', (tester) async {
        await pump(
          tester,
          const BaraedaCard(tone: BaraedaCardTone.outline, child: Text('내용')),
        );
        final box = tester
            .widgetList<Container>(find.byType(Container))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.border != null);
        expect((box.border! as Border).top.color, colors.borderDefault);
      });
    });
  }
}
