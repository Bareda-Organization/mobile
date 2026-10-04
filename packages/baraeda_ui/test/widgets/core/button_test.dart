import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/theme/baraeda_theme.dart';
import 'package:baraeda_ui/widgets/core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [BaraedaButton]의 배경색이 배리언트별로 테마의 `BaraedaColors` 값을
/// 그대로 쓰는지 확인한다 — 하드코딩이 아니라 테마 참조라는 것을 증명한다.
void main() {
  Future<Color> buttonBackground(
    WidgetTester tester, {
    required BaraedaButtonVariant variant,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BaraedaTheme.light(),
        home: Scaffold(
          body: BaraedaButton(
            label: '확인하기',
            variant: variant,
            onPressed: () {},
          ),
        ),
      ),
    );

    final ink = tester.widget<Ink>(find.byType(Ink));
    final decoration = ink.decoration! as BoxDecoration;
    return decoration.color!;
  }

  const colors = BaraedaColors.light;

  testWidgets('primary 배경은 accentPrimary', (tester) async {
    final bg = await buttonBackground(
      tester,
      variant: BaraedaButtonVariant.primary,
    );
    expect(bg, colors.accentPrimary);
  });

  testWidgets('secondary 배경은 surfaceCard', (tester) async {
    final bg = await buttonBackground(
      tester,
      variant: BaraedaButtonVariant.secondary,
    );
    expect(bg, colors.surfaceCard);
  });

  testWidgets('soft 배경은 accentPrimarySoft', (tester) async {
    final bg = await buttonBackground(
      tester,
      variant: BaraedaButtonVariant.soft,
    );
    expect(bg, colors.accentPrimarySoft);
  });

  testWidgets('ghost 배경은 투명', (tester) async {
    final bg = await buttonBackground(
      tester,
      variant: BaraedaButtonVariant.ghost,
    );
    expect(bg, Colors.transparent);
  });

  testWidgets('danger 배경은 dangerSolid(#C93F2C)', (tester) async {
    final bg = await buttonBackground(
      tester,
      variant: BaraedaButtonVariant.danger,
    );
    expect(bg, colors.dangerSolid);
  });

  testWidgets('onPressed가 null이면 흐리게 하지 않고 꺼진 면·글자를 쓴다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BaraedaTheme.light(),
        home: const Scaffold(body: BaraedaButton(label: '확인하기')),
      ),
    );

    // 예전에는 전체를 0.42 로 흐렸다 — 시안은 꺼진 면(#ECEEED) 위에 글자를 읽을 수 있게 둔다.
    expect(find.byType(Opacity), findsNothing);
    final ink = tester.widget<Ink>(find.byType(Ink));
    expect((ink.decoration! as BoxDecoration).color, colors.disabledSurface);
    expect(
      tester.widget<Text>(find.text('확인하기')).style!.color,
      colors.disabledText,
    );
  });
}
