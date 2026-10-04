// 상태 칩 5종 — 색만으로 가르지 않도록 모양이 다르다(시안 kit "상태 칩 5종").
// 종료 ■ · 이동 중 ▶ · 확정 ● · 대기 ○ · 위험 ▲. 미등원은 회색 끝남(■).
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? BaraedaTheme.light(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  const colors = BaraedaColors.light;

  group('상태마다 모양이 다르다', () {
    const expected = <BaraedaStatus, BaraedaStatusShape>{
      BaraedaStatus.idle: BaraedaStatusShape.square,
      BaraedaStatus.moving: BaraedaStatusShape.triangleRight,
      BaraedaStatus.boarded: BaraedaStatusShape.circle,
      BaraedaStatus.waiting: BaraedaStatusShape.ring,
      BaraedaStatus.missed: BaraedaStatusShape.triangleUp,
    };

    for (final MapEntry(key: status, value: shape) in expected.entries) {
      testWidgets('${status.name} 칩은 $shape 를 그린다', (tester) async {
        await tester.pumpWidget(_host(BaraedaStatusPill(status: status)));
        final mark = tester.widget<BaraedaStatusMark>(
          find.byType(BaraedaStatusMark),
        );
        expect(mark.shape, shape);
      });
    }

    test('5종의 모양이 서로 전부 다르다 — 색만으로 가르지 않는다', () {
      final shapes = BaraedaStatus.values.map((s) => s.shape).toSet();
      expect(shapes.length, 5);
      expect(BaraedaStatus.values.length, 5);
    });
  });

  group('모양 색은 시안 `--c-*` 다', () {
    final expected = <BaraedaStatus, Color>{
      BaraedaStatus.idle: colors.shapeIdle,
      BaraedaStatus.moving: colors.shapeMoving,
      BaraedaStatus.boarded: colors.shapeBoarded,
      BaraedaStatus.waiting: colors.shapeWait,
      BaraedaStatus.missed: colors.dangerSolid,
    };
    for (final MapEntry(key: status, value: color) in expected.entries) {
      testWidgets('${status.name} 칩의 모양 색', (tester) async {
        await tester.pumpWidget(_host(BaraedaStatusPill(status: status)));
        expect(
          tester
              .widget<BaraedaStatusMark>(find.byType(BaraedaStatusMark))
              .color,
          color,
        );
      });
    }
  });

  testWidgets('dot 을 끄면 모양을 그리지 않는다', (tester) async {
    await tester.pumpWidget(
      _host(const BaraedaStatusPill(status: BaraedaStatus.boarded, dot: false)),
    );
    expect(find.byType(BaraedaStatusMark), findsNothing);
  });

  testWidgets('대기 칩은 면이 옅은 초록이고 모양 색 테두리가 있다', (tester) async {
    await tester.pumpWidget(
      _host(const BaraedaStatusPill(status: BaraedaStatus.waiting)),
    );
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(BaraedaStatusPill),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, colors.statusWaitSoft);
    expect((decoration.border! as Border).top.color, colors.shapeWait);
  });

  testWidgets('큰 칩(lg)은 높이 32 · 글자 14, 기본은 높이 26 · 글자 13', (tester) async {
    await tester.pumpWidget(
      _host(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BaraedaStatusPill(status: BaraedaStatus.boarded),
            BaraedaStatusPill(
              status: BaraedaStatus.boarded,
              size: BaraedaStatusPillSize.lg,
            ),
          ],
        ),
      ),
    );
    final pills = find.byType(BaraedaStatusPill);
    expect(tester.getSize(pills.at(0)).height, greaterThanOrEqualTo(26));
    expect(tester.getSize(pills.at(1)).height, greaterThanOrEqualTo(32));
    final texts = tester
        .widgetList<Text>(find.text('승차 완료'))
        .map((t) => t.style!.fontSize)
        .toList();
    expect(texts, [13, 14]);
  });

  testWidgets('낭독은 상태 문구 하나만 읽는다', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const BaraedaStatusPill(status: BaraedaStatus.missed, label: '미승차'),
      ),
    );
    expect(find.bySemanticsLabel('미승차'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('미등원은 회색 끝남(■) 이고 위험(▲)이 아니다', (tester) async {
    await tester.pumpWidget(
      _host(const StudentRow(name: '박지후', ride: RideStatus.absent)),
    );
    final pill = tester.widget<BaraedaStatusPill>(
      find.byType(BaraedaStatusPill),
    );
    expect(pill.status, BaraedaStatus.idle);
    expect(pill.label, '미등원');
    expect(
      tester.widget<BaraedaStatusMark>(find.byType(BaraedaStatusMark)).shape,
      BaraedaStatusShape.square,
    );
  });
}
