// 큰 선택 칸(라디오) — 일일 변경의 회차 고르기 · 가입의 학원 고르기(시안 `.p-choice`).
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: BaraedaTheme.light(),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 360, child: child),
    ),
  ),
);

void main() {
  _listRowWrapTests();
  testWidgets('누르면 콜백이 불리고 선택 상태가 낭독에 실린다', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        BaraedaChoiceTile(
          title: '하원 · 14:40 출발',
          selected: true,
          onTap: () => taps++,
        ),
      ),
    );

    await tester.tap(find.text('하원 · 14:40 출발'));
    expect(taps, 1);
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byType(BaraedaChoiceTile)),
      isSemantics(label: '하원 · 14:40 출발', isSelected: true, isButton: true),
    );
    handle.dispose();
  });

  testWidgets('이유를 주면 꺼진 칸이다 — 누름에 반응하지 않고 이유가 보조 줄 자리에 보인다', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        BaraedaChoiceTile(
          title: '등원 · 12:20 출발',
          subtitle: '행복마을 입구 · 2호차',
          disabledReason: '운행이 끝났어요',
          onTap: () => taps++,
        ),
      ),
    );

    await tester.tap(find.text('등원 · 12:20 출발'));
    expect(taps, 0);
    expect(find.text('운행이 끝났어요'), findsOneWidget);
    expect(find.text('행복마을 입구 · 2호차'), findsNothing);
  });

  testWidgets('꺼진 칸의 글자는 기존 보조 글자색(#5C665F)이다 — 새 색을 만들지 않는다(Ruling 829)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const BaraedaChoiceTile(title: '등원', disabledReason: '운행이 끝났어요')),
    );

    final title = tester.widget<Text>(find.text('등원'));
    expect(title.style?.color, BaraedaColors.light.textSecondary);
  });

  testWidgets('선택된 칸은 초록 2px 테두리, 아닌 칸은 1px 테두리다', (tester) async {
    await tester.pumpWidget(
      _host(
        const Column(
          children: [
            BaraedaChoiceTile(
              key: Key('on'),
              title: 'A',
              selected: true,
              onTap: _noop,
            ),
            BaraedaChoiceTile(key: Key('off'), title: 'B', onTap: _noop),
          ],
        ),
      ),
    );

    BoxDecoration decorationOf(Key key) =>
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byKey(key),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;

    final on = decorationOf(const Key('on')).border! as Border;
    final off = decorationOf(const Key('off')).border! as Border;
    expect(on.top.width, 2);
    expect(on.top.color, BaraedaColors.light.accentPrimary);
    expect(off.top.width, 1);
  });
}

void _noop() {}

// R48 — 목록 칸 보조 줄의 낱말 단위 줄바꿈(기본은 예전 그대로).
void _listRowWrapTests() {
  testWidgets('wrapSubtitleByWord 를 켜면 보조 줄이 WordWrapText 이고, 기본은 그냥 Text 다', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Column(
          children: [
            BaraedaListRow(title: '가', subtitle: '기본 줄'),
            BaraedaListRow(
              title: '나',
              subtitle: '낱말 줄',
              wrapSubtitleByWord: true,
            ),
          ],
        ),
      ),
    );

    expect(find.byType(WordWrapText), findsOneWidget);
    expect(find.text('기본 줄'), findsOneWidget);
  });
}
