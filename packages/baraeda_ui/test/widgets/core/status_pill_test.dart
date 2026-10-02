import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/theme/baraeda_theme.dart';
import 'package:baraeda_ui/widgets/core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [BaraedaStatusPill]이 하드코딩 색이 아니라 라이트·다크 테마의
/// `BaraedaColors` 값을 그대로 읽는지 확인한다 — 4개 상태 × 2개 테마.
void main() {
  Future<Color> pillDotColor(
    WidgetTester tester, {
    required BaraedaStatus status,
    required ThemeData theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: BaraedaStatusPill(status: status, label: '상태'),
        ),
      ),
    );

    final dotFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
    );
    final dot = tester.widget<Container>(dotFinder);
    final decoration = dot.decoration! as BoxDecoration;
    return decoration.color!;
  }

  group('BaraedaStatusPill 색 매핑 — 라이트 테마', () {
    final theme = BaraedaTheme.light();
    const colors = BaraedaColorsFixture.light;

    testWidgets('boarded는 statusBoarded', (tester) async {
      final color = await pillDotColor(
        tester,
        status: BaraedaStatus.boarded,
        theme: theme,
      );
      expect(color, colors.statusBoarded);
    });

    testWidgets('moving은 statusMoving', (tester) async {
      final color = await pillDotColor(
        tester,
        status: BaraedaStatus.moving,
        theme: theme,
      );
      expect(color, colors.statusMoving);
    });

    testWidgets('missed는 statusMissed', (tester) async {
      final color = await pillDotColor(
        tester,
        status: BaraedaStatus.missed,
        theme: theme,
      );
      expect(color, colors.statusMissed);
    });

    testWidgets('idle은 statusIdle', (tester) async {
      final color = await pillDotColor(
        tester,
        status: BaraedaStatus.idle,
        theme: theme,
      );
      expect(color, colors.statusIdle);
    });
  });

  group('BaraedaStatusPill 색 매핑 — 다크 테마', () {
    final theme = BaraedaTheme.dark();
    const colors = BaraedaColorsFixture.dark;

    testWidgets('boarded는 statusBoarded', (tester) async {
      final color = await pillDotColor(
        tester,
        status: BaraedaStatus.boarded,
        theme: theme,
      );
      expect(color, colors.statusBoarded);
    });

    testWidgets('moving은 statusMoving', (tester) async {
      final color = await pillDotColor(
        tester,
        status: BaraedaStatus.moving,
        theme: theme,
      );
      expect(color, colors.statusMoving);
    });

    testWidgets('missed는 statusMissed', (tester) async {
      final color = await pillDotColor(
        tester,
        status: BaraedaStatus.missed,
        theme: theme,
      );
      expect(color, colors.statusMissed);
    });

    testWidgets('idle은 statusIdle', (tester) async {
      final color = await pillDotColor(
        tester,
        status: BaraedaStatus.idle,
        theme: theme,
      );
      expect(color, colors.statusIdle);
    });
  });
}

/// 라이트·다크 `BaraedaColors` 인스턴스를 테스트에서 손쉽게 참조하기 위한
/// 별칭 — 위젯 쪽 임포트만으로는 `BaraedaColors.light/.dark` 정적 필드가
/// 바로 안 보여서 짧게 감싼다.
abstract final class BaraedaColorsFixture {
  static const BaraedaColors light = BaraedaColors.light;
  static const BaraedaColors dark = BaraedaColors.dark;
}
