// 두 갈래를 합치면서 조율자가 직접 고친 2건을 고정하는 시험.
// 조율자 편집에는 게이트 리뷰가 붙지 않으므로(`parallel-agents-git.md §10`)
// 되돌렸을 때 실패하는 시험이 없으면 그 편집은 고정되지 않은 것이다.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: BaraedaTheme.light(),
  home: Scaffold(body: child),
);

void main() {
  group('BaraedaStatusPill 기본 라벨', () {
    // 정본: 디자인 시스템 components/core/StatusPill.d.ts — "pill 안 문구.
    // 비우면 상태 기본 라벨". label 을 필수로 두면 이 규칙이 사라진다.
    const expected = {
      BaraedaStatus.boarded: '승차 완료',
      BaraedaStatus.moving: '이동 중',
      BaraedaStatus.missed: '미탑승',
      BaraedaStatus.idle: '운행 전',
    };

    for (final entry in expected.entries) {
      testWidgets('${entry.key.name} 은 문구를 안 주면 "${entry.value}"', (
        tester,
      ) async {
        await tester.pumpWidget(_wrap(BaraedaStatusPill(status: entry.key)));
        expect(find.text(entry.value), findsOneWidget);
      });
    }

    testWidgets('문구를 주면 그 값이 기본 라벨을 대신한다', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const BaraedaStatusPill(
            status: BaraedaStatus.moving,
            label: '이동 중 · 지연',
          ),
        ),
      );
      expect(find.text('이동 중 · 지연'), findsOneWidget);
      expect(find.text('이동 중'), findsNothing);
    });
  });

  testWidgets('ElevatedButton 기본 스타일이 가로를 무한대로 강제하지 않는다', (tester) async {
    // Size.fromHeight 는 가로를 double.infinity 로 둔다. 그 상태로 Row 안에
    // 놓으면 "BoxConstraints forces an infinite width" 로 죽는다.
    await tester.pumpWidget(
      _wrap(
        Row(
          children: [
            ElevatedButton(onPressed: () {}, child: const Text('노선 강제 추가')),
            ElevatedButton(onPressed: () {}, child: const Text('명단 내려받기')),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('노선 강제 추가'), findsOneWidget);

    // 최소 터치 영역 48 은 그대로 지켜져야 한다 — 고치면서 잃으면 안 되는 값이다.
    final size = tester.getSize(find.byType(ElevatedButton).first);
    expect(size.height, greaterThanOrEqualTo(BaraedaSpacing.tapMin));
    expect(size.width, lessThan(400));
  });
}
