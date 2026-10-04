import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/theme/baraeda_theme.dart';
import 'package:baraeda_ui/widgets/core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [BaraedaStatusPill]이 하드코딩 색이 아니라 라이트·다크 테마의
/// `BaraedaColors` 값을 그대로 읽는지 확인한다 — 5개 상태 × 2개 테마.
/// 글자색 · 면 · 모양 색 셋 다 테마를 거친다.
void main() {
  final themes = <String, (ThemeData, BaraedaColors)>{
    '라이트': (BaraedaTheme.light(), BaraedaColors.light),
    '다크': (BaraedaTheme.dark(), BaraedaColors.dark),
  };

  (Color text, Color soft, Color shape) expected(
    BaraedaStatus status,
    BaraedaColors c,
  ) => switch (status) {
    BaraedaStatus.boarded => (
      c.statusBoarded,
      c.statusBoardedSoft,
      c.shapeBoarded,
    ),
    BaraedaStatus.moving => (c.statusMoving, c.statusMovingSoft, c.shapeMoving),
    BaraedaStatus.missed => (c.statusMissed, c.statusMissedSoft, c.dangerSolid),
    BaraedaStatus.idle => (c.statusIdle, c.statusIdleSoft, c.shapeIdle),
    BaraedaStatus.waiting => (c.statusWait, c.statusWaitSoft, c.shapeWait),
  };

  for (final MapEntry(key: themeName, value: (theme, colors))
      in themes.entries) {
    for (final status in BaraedaStatus.values) {
      testWidgets('$themeName 테마 ${status.name} — 글자 · 면 · 모양 색', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: BaraedaStatusPill(status: status, label: '상태'),
            ),
          ),
        );
        final (text, soft, shape) = expected(status, colors);

        expect(tester.widget<Text>(find.text('상태')).style!.color, text);
        final decoration =
            tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: find.byType(BaraedaStatusPill),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        expect(decoration.color, soft);
        expect(
          tester
              .widget<BaraedaStatusMark>(find.byType(BaraedaStatusMark))
              .color,
          shape,
        );
      });
    }
  }
}
