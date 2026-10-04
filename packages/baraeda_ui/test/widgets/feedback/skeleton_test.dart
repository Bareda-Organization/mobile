// 불러오는 중 뼈대 — 반짝임은 투명도만, 움직임 줄이기가 켜지면 멈춘다(시안 kit "불러오는 중 · 뼈대").
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  theme: BaraedaTheme.light(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
    child: child!,
  ),
  home: Scaffold(body: Center(child: child)),
);

double _opacity(WidgetTester tester) =>
    tester.widget<Opacity>(find.byType(Opacity).first).opacity;

void main() {
  testWidgets('움직임 줄이기가 켜지면 뼈대는 정지한다 — 애니메이션이 돌지 않는다', (tester) async {
    await tester.pumpWidget(
      _host(const BaraedaSkeleton(width: 120), reduceMotion: true),
    );
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pump(const Duration(milliseconds: 700));
    expect(_opacity(tester), 1);
  });

  testWidgets('기본은 1.4초 주기로 투명도만 깜빡인다(가운데 지점에서 0.5)', (tester) async {
    await tester.pumpWidget(_host(const BaraedaSkeleton(width: 120)));
    expect(tester.hasRunningAnimations, isTrue);
    expect(_opacity(tester), 1);

    await tester.pump(const Duration(milliseconds: 700));
    expect(_opacity(tester), closeTo(0.5, 0.02));

    await tester.pump(const Duration(milliseconds: 700));
    expect(_opacity(tester), closeTo(1, 0.02));
  });

  testWidgets('뼈대는 이동 · 크기 변화 없이 같은 자리 · 같은 크기다', (tester) async {
    await tester.pumpWidget(_host(const BaraedaSkeleton(width: 120)));
    final first = tester.getRect(find.byType(BaraedaSkeleton));
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.getRect(find.byType(BaraedaSkeleton)), first);
    expect(first.size, const Size(120, 16));
  });

  testWidgets('다른 화면으로 가면 애니메이션이 정리된다', (tester) async {
    await tester.pumpWidget(_host(const BaraedaSkeleton(width: 120)));
    await tester.pumpWidget(_host(const SizedBox()));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('목록 뼈대 행은 최종 행과 같은 높이(56 이상)이고 낭독은 "불러오는 중" 하나', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(const BaraedaSkeletonList(), reduceMotion: true),
    );
    expect(
      tester.getSize(find.byType(BaraedaSkeletonRow).first).height,
      greaterThanOrEqualTo(BaraedaSpacing.rowMinHeight),
    );
    expect(find.byType(BaraedaSkeletonRow), findsNWidgets(3));
    expect(find.bySemanticsLabel('불러오는 중'), findsOneWidget);
    handle.dispose();
  });
}
