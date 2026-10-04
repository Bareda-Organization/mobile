// R48 시안 부품 — 목록 칸 · 필터 알약 · 단추 한 쌍 · 비상 · 지도 단추 · 영수증 · 아래 탭 막대.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double width = 360, ThemeData? theme}) =>
    MaterialApp(
      theme: theme ?? BaraedaTheme.light(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    );

void main() {
  const colors = BaraedaColors.light;

  group('목록 칸', () {
    testWidgets('높이는 56 이상이고 누를 수 있다', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(BaraedaListRow(title: '비밀번호 변경', onTap: () => taps++)),
      );
      expect(
        tester.getSize(find.byType(BaraedaListRow)).height,
        greaterThanOrEqualTo(BaraedaSpacing.rowMinHeight),
      );
      await tester.tap(find.text('비밀번호 변경'));
      expect(taps, 1);
    });

    testWidgets('보조 줄은 두 줄까지 보인다(C2) — 한 줄 `…` 로 핵심 정보를 자르지 않는다', (
      tester,
    ) async {
      const sub =
          '오늘 탑승 학생 없음 · 미등원 2명 · 보호자 연락 가능한 학생이 한 명도 없어서 오늘은 전화를 걸 곳이 없음';
      await tester.pumpWidget(
        _host(const BaraedaListRow(title: '2호차 등원', subtitle: sub), width: 220),
      );
      final text = tester.widget<Text>(find.text(sub));
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('승하차지 이름은 두 줄에서 `…`, 사람 이름은 자르지 않는다', (tester) async {
      const place = '부천중동 센트럴파크 푸르지오 2단지 아파트 정문 앞 버스정류장 (구 중동초등학교 건너편)';
      const person = '김가나다라마바사아자차카타파하김가나다라마바사아자차카타파하';
      await tester.pumpWidget(
        _host(
          const Column(
            children: [
              BaraedaListRow(title: place),
              BaraedaListRow(title: person, titleIsPersonName: true),
            ],
          ),
          width: 200,
        ),
      );
      final placeText = tester.widget<Text>(find.text(place));
      expect(placeText.maxLines, 2);
      expect(placeText.overflow, TextOverflow.ellipsis);
      final personText = tester.widget<Text>(find.text(person));
      expect(personText.maxLines, isNull);
      final paragraph = tester.renderObject<RenderParagraph>(find.text(person));
      expect(paragraph.didExceedMaxLines, isFalse);
    });

    testWidgets('onTap 이 없으면 눌러도 반응이 없다', (tester) async {
      await tester.pumpWidget(_host(const BaraedaListRow(title: '안내')));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('안내')),
      );
      await tester.pump(BaraedaDuration.press);
      final decoration =
          tester
                  .widget<AnimatedContainer>(
                    find.byType(AnimatedContainer).first,
                  )
                  .decoration!
              as BoxDecoration;
      // 누를 수 없는 줄은 눌러도 면 색이 바뀌지 않는다.
      expect(decoration.color, Colors.transparent);
      await gesture.up();
    });
  });

  group('필터 알약', () {
    testWidgets('높이 44, 선택되면 초록 면 + 흰 글자', (tester) async {
      await tester.pumpWidget(
        _host(const BaraedaFilterPill(label: '전체 14', selected: true)),
      );
      expect(
        tester.getSize(find.byType(BaraedaFilterPill)).height,
        greaterThanOrEqualTo(44),
      );
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(BaraedaFilterPill),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((box.decoration as BoxDecoration).color, colors.accentPrimary);
      expect(
        tester.widget<Text>(find.text('전체 14')).style!.color,
        colors.textInverse,
      );
    });

    testWidgets('이름이 길면 이 칸만 줄어 `…` 가 된다', (tester) async {
      const name = '아주아주아주아주아주아주아주 긴 자녀 이름 알약';
      await tester.pumpWidget(
        _host(
          const Row(
            children: [Flexible(child: BaraedaFilterPill(label: name))],
          ),
          width: 140,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<Text>(find.text(name)).overflow,
        TextOverflow.ellipsis,
      );
    });
  });

  group('단추 한 쌍(C1)', () {
    testWidgets('주 단추가 보조보다 1.7 : 1 로 넓다', (tester) async {
      await tester.pumpWidget(
        _host(
          BaraedaButtonRow(
            children: [
              BaraedaButton(label: '탑승', onPressed: () {}),
              BaraedaButton(
                label: '미승차',
                variant: BaraedaButtonVariant.secondary,
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
      final a = tester.getSize(find.widgetWithText(BaraedaButton, '탑승')).width;
      final b = tester.getSize(find.widgetWithText(BaraedaButton, '미승차')).width;
      expect(a / b, closeTo(1.7, 0.02));
    });
  });

  group('비상 버튼 3형태', () {
    testWidgets('머리줄 알약은 높이 44 · 위험 면, 낭독은 `비상`', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(BaraedaSosButton(onPressed: () {})));
      expect(
        tester.getSize(find.byType(BaraedaSosButton)).height,
        greaterThanOrEqualTo(44),
      );
      expect(find.bySemanticsLabel('비상'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('떠 있는 둥근 단추는 64×64', (tester) async {
      await tester.pumpWidget(
        _host(
          // 부모가 폭을 강제하지 않는 자리(`Positioned`)와 같게 느슨하게 둔다.
          const Align(
            alignment: Alignment.topLeft,
            child: BaraedaSosButton(form: BaraedaSosForm.floating),
          ),
        ),
      );
      expect(tester.getSize(find.byType(BaraedaSosButton)), const Size(64, 64));
    });

    testWidgets('긴 단추는 폭 전체 · 위험 면 · `비상 알림 보내기`', (tester) async {
      await tester.pumpWidget(
        _host(BaraedaSosButton(form: BaraedaSosForm.wide, onPressed: () {})),
      );
      expect(find.text('비상 알림 보내기'), findsOneWidget);
      expect(tester.getSize(find.byType(BaraedaSosButton)).width, 360);
      final ink = tester.widget<Ink>(find.byType(Ink));
      expect((ink.decoration! as BoxDecoration).color, colors.dangerSolid);
    });
  });

  group('지도 단추', () {
    testWidgets('아이콘만이면 48×48, 글자가 있으면 높이 44 알약', (tester) async {
      await tester.pumpWidget(
        _host(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BaraedaMapButton(
                icon: 'crosshair',
                semanticLabel: '내 위치',
                onPressed: () {},
              ),
              BaraedaMapButton(
                icon: 'route',
                semanticLabel: '경로',
                label: '노선 보기',
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
      final sizes = tester
          .widgetList<BaraedaMapButton>(find.byType(BaraedaMapButton))
          .map((w) => tester.getSize(find.byWidget(w)))
          .toList();
      expect(sizes[0], const Size(48, 48));
      expect(sizes[1].height, 44);
    });

    testWidgets('다크 구역에서도 지도 위 단추는 흰 면 + 잉크 글자', (tester) async {
      await tester.pumpWidget(
        _host(
          BaraedaMapButton(
            icon: 'crosshair',
            semanticLabel: '내 위치',
            onPressed: () {},
          ),
          theme: BaraedaTheme.dark(),
        ),
      );
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(BaraedaMapButton),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        (box.decoration as BoxDecoration).color,
        BaraedaColors.dark.mapControlSurface,
      );
      expect(BaraedaColors.dark.mapControlSurface, const Color(0xFFFFFFFF));
    });
  });

  group('제출 영수증', () {
    testWidgets('제목과 신청 내용을 이름 · 값 줄로 보인다', (tester) async {
      await tester.pumpWidget(
        _host(
          const BaraedaReceiptCard(
            title: '승인 요청을 보냈어요',
            rows: [
              BaraedaReceiptRow('회차', '하원 · 14:40 출발'),
              BaraedaReceiptRow('변경', '승하차지 변경'),
            ],
          ),
        ),
      );
      expect(find.text('승인 요청을 보냈어요'), findsOneWidget);
      expect(find.text('하원 · 14:40 출발'), findsOneWidget);
      expect(find.text('변경'), findsOneWidget);
    });
  });

  group('아래 탭 막대', () {
    final items = [
      const BaraedaTabItem(icon: 'list', label: '명단'),
      const BaraedaTabItem(icon: 'bus', label: '회차'),
      const BaraedaTabItem(icon: 'bell', label: '알림', badge: 2),
      const BaraedaTabItem(icon: 'user-round', label: '내 정보'),
    ];

    testWidgets('한 칸 높이 56 이상 · 현재 탭은 연초록 면 + 초록 글자', (tester) async {
      await tester.pumpWidget(
        _host(BaraedaTabBar(items: items, currentIndex: 0, onChanged: (_) {})),
      );
      final first = find.widgetWithText(BaraedaPressable, '명단');
      expect(tester.getSize(first).height, greaterThanOrEqualTo(56));
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: first, matching: find.byType(DecoratedBox)).first,
      );
      expect((box.decoration as BoxDecoration).color, colors.navActiveBg);
      expect(
        tester.widget<Text>(find.text('명단')).style!.color,
        colors.navActiveText,
      );
    });

    testWidgets('Scaffold 아래 막대 자리에서도 화면 전체를 먹지 않고 본문이 남는다', (tester) async {
      // 2026-10-04 시뮬레이터에서 견본을 띄웠을 때 막대가 화면 전체 높이가 되어 본문이 사라졌다 —
      // `Scaffold.bottomNavigationBar` 는 세로 제약이 느슨해서 Column 이 최대 높이를 잡는다.
      await tester.pumpWidget(
        MaterialApp(
          theme: BaraedaTheme.light(),
          home: Scaffold(
            body: const Center(child: Text('본문')),
            bottomNavigationBar: BaraedaTabBar(
              items: items,
              currentIndex: 0,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(BaraedaTabBar)).height, lessThan(100));
      expect(tester.getSize(find.text('본문')).height, greaterThan(0));
      expect(tester.getCenter(find.text('본문')).dy, lessThan(500));
    });

    testWidgets('현재 탭의 연초록 면이 칸 폭을 가득 채운다(내용 폭으로 줄지 않는다)', (tester) async {
      await tester.pumpWidget(
        _host(BaraedaTabBar(items: items, currentIndex: 0, onChanged: (_) {})),
      );
      final cell = find.widgetWithText(BaraedaPressable, '명단');
      // 칸(탭 영역)이 아니라 **색이 칠해진 면**의 폭을 잰다 — 칸은 Stack 이 제약대로 채워 줘도
      // 면은 느슨한 제약에서 내용 폭으로 줄 수 있다(2026-10-04 시뮬레이터에서 좁은 알약으로 보였다).
      final face = find
          .descendant(of: cell, matching: find.byType(DecoratedBox))
          .first;
      expect(tester.getSize(face).width, tester.getSize(cell).width);
      expect(tester.getSize(face).width, greaterThan(70));
    });

    testWidgets('배지는 건수, 99 를 넘으면 99+', (tester) async {
      await tester.pumpWidget(
        _host(
          BaraedaTabBar(
            items: const [
              BaraedaTabItem(icon: 'bell', label: '알림', badge: 120),
              BaraedaTabItem(icon: 'list', label: '명단', badge: 2),
            ],
            currentIndex: 0,
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('99+'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('탭을 누르면 인덱스가 올라가고, 낭독은 새 알림 건수까지 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      int? picked;
      await tester.pumpWidget(
        _host(
          BaraedaTabBar(
            items: items,
            currentIndex: 0,
            onChanged: (i) => picked = i,
          ),
        ),
      );
      expect(find.bySemanticsLabel('알림, 새 알림 2건'), findsOneWidget);
      await tester.tap(find.text('회차'));
      expect(picked, 1);
      handle.dispose();
    });
  });
}
