// 다크 구역(운행 모드) — 안쪽은 항상 다크 색이고, 시트 · 대화상자 · 토스트는 움직임 없이 뜬다.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('구역 안은 라이트 앱 한가운데서도 다크 색을 쓴다', (tester) async {
    late BaraedaColors inside;
    late BaraedaColors outside;
    await tester.pumpWidget(
      MaterialApp(
        theme: BaraedaTheme.light(),
        home: Builder(
          builder: (context) {
            outside = context.colors;
            return BaraedaDriveZone(
              child: Builder(
                builder: (context) {
                  inside = context.colors;
                  return const SizedBox();
                },
              ),
            );
          },
        ),
      ),
    );
    expect(outside.bgBase, BaraedaColors.light.bgBase);
    expect(inside.bgBase, BaraedaColors.dark.bgBase);
  });

  testWidgets('열리는 움직임: 기본 full · 줄이기 fadeOnly · 구역 none(구역이 우선)', (
    tester,
  ) async {
    BaraedaOpenMotion? plain;
    BaraedaOpenMotion? reduced;
    BaraedaOpenMotion? zone;
    BaraedaOpenMotion? zoneReduced;
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Builder(
              builder: (c) {
                plain = BaraedaOpenMotion.of(c);
                return const SizedBox();
              },
            ),
            MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Builder(
                builder: (c) {
                  reduced = BaraedaOpenMotion.of(c);
                  return const SizedBox();
                },
              ),
            ),
            BaraedaDriveZone(
              child: Builder(
                builder: (c) {
                  zone = BaraedaOpenMotion.of(c);
                  return const SizedBox();
                },
              ),
            ),
            MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: BaraedaDriveZone(
                child: Builder(
                  builder: (c) {
                    zoneReduced = BaraedaOpenMotion.of(c);
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
    expect(plain, BaraedaOpenMotion.full);
    expect(reduced, BaraedaOpenMotion.fadeOnly);
    expect(zone, BaraedaOpenMotion.none);
    expect(zoneReduced, BaraedaOpenMotion.none);
  });

  testWidgets('구역 안에서 연 대화상자는 페이드 없이 바로 보인다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BaraedaTheme.light(),
        home: BaraedaDriveZone(
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showBaraedaConfirmDialog(
                  context: context,
                  title: '운행을 시작할까요?',
                  confirmLabel: '운행 시작',
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pump();
    expect(find.text('운행을 시작할까요?'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(BaraedaDialog),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
  });
}
