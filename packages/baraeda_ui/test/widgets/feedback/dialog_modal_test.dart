// 대화상자 시맨틱 · 단추 쌓기 — 뒤 화면이 읽히지 않는다(웹 `aria-modal` 대응, C5).
// 위험 확인은 빨강 위 · 닫기 아래, 3단 선택은 주 · 위험 테두리 · 닫기 순서(시안 kit).
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _screen(Widget dialog) => MaterialApp(
  theme: BaraedaTheme.light(),
  home: Scaffold(
    body: Stack(
      children: [
        const Align(alignment: Alignment.topLeft, child: Text('뒤 화면 본문')),
        dialog,
      ],
    ),
  ),
);

void main() {
  testWidgets('대화상자가 떠 있으면 뒤 화면은 낭독 트리에서 빠진다', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _screen(const BaraedaDialog(title: '삭제할까요?', body: '되돌릴 수 없어요.')),
    );
    expect(find.bySemanticsLabel(RegExp('뒤 화면 본문')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('삭제할까요')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('대화상자가 없으면 같은 글자는 낭독 트리에 있다(위 시험의 대조군)', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_screen(const SizedBox()));
    expect(find.bySemanticsLabel(RegExp('뒤 화면 본문')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('actions 는 세로로 쌓이고 폭이 같다', (tester) async {
    await tester.pumpWidget(
      _screen(
        BaraedaDialog(
          title: '로그아웃할까요?',
          actions: [
            BaraedaButton(label: '대기열 3건 먼저 보기', block: true, onPressed: () {}),
            BaraedaButton(
              label: '그래도 로그아웃',
              block: true,
              variant: BaraedaButtonVariant.secondary,
              onPressed: () {},
            ),
            BaraedaButton(
              label: '닫기',
              block: true,
              variant: BaraedaButtonVariant.ghost,
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
    final a = tester.getRect(find.text('대기열 3건 먼저 보기'));
    final b = tester.getRect(find.text('그래도 로그아웃'));
    final c = tester.getRect(find.text('닫기'));
    expect(a.top, lessThan(b.top));
    expect(b.top, lessThan(c.top));
    final widths = tester
        .widgetList<Ink>(find.byType(Ink))
        .map((_) => 0)
        .length;
    expect(widths, 3);
    final inks = find.byType(Ink);
    expect(tester.getSize(inks.at(0)).width, tester.getSize(inks.at(1)).width);
  });

  testWidgets('위험 확인 대화상자: 빨강(위) · 닫기(아래), 빨강을 누르면 true', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: BaraedaTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => result = await showBaraedaConfirmDialog(
                  context: context,
                  title: '미승차 처리할까요?',
                  confirmLabel: '미승차 처리',
                  cancelLabel: '닫기',
                  danger: true,
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    final confirm = find.text('미승차 처리');
    final close = find.text('닫기');
    expect(tester.getRect(confirm).top, lessThan(tester.getRect(close).top));
    final confirmInk = tester.widget<Ink>(
      find.ancestor(of: confirm, matching: find.byType(Ink)),
    );
    expect(
      (confirmInk.decoration! as BoxDecoration).color,
      BaraedaColors.light.dangerSolid,
    );

    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('열릴 때 200ms 로 나타난다(운행 중 다크 구역은 바로)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BaraedaTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showBaraedaConfirmDialog(
                context: context,
                title: '확인',
                confirmLabel: '확인',
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.byType(BaraedaDialog),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, lessThan(1));
    await tester.pump(const Duration(milliseconds: 120));
    expect(fade.opacity.value, 1);
  });
}
