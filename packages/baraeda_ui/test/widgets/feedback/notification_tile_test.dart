// R44 — 알림 목록 행. 안 읽음/읽음이 한눈에 갈리는지 · 중요 표시 · 낭독 한 번 · 누르는 영역을 잰다.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationTile _tile({
  bool unread = false,
  bool important = false,
  String? body = '김철수 학생이 탄 버스가 승하차지 근처에 도착했습니다.',
  VoidCallback? onTap,
  String icon = 'map-pin',
  BaraedaStatus status = BaraedaStatus.moving,
}) => NotificationTile(
  icon: icon,
  status: status,
  kindLabel: '미승차',
  title: '미승차 안내',
  body: body,
  time: '8:37',
  timeSpoken: '오전 8시 37분',
  unread: unread,
  important: important,
  onTap: onTap,
);

Future<void> _pump(WidgetTester tester, Widget child, {ThemeData? theme}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: theme ?? BaraedaTheme.light(),
        home: Scaffold(body: child),
      ),
    );

/// 행의 바탕색 — 행 전체를 칠하는 `Material` 하나.
Color? _rowColor(WidgetTester tester) => tester
    .widget<Material>(
      find
          .descendant(
            of: find.byType(NotificationTile),
            matching: find.byType(Material),
          )
          .first,
    )
    .color;

FontWeight? _titleWeight(WidgetTester tester) =>
    tester.widget<Text>(find.text('미승차 안내')).style?.fontWeight;

void main() {
  group('안 읽음 / 읽음', () {
    testWidgets('안 읽음은 바탕이 칠해지고 읽음은 바탕이 없다', (tester) async {
      await _pump(tester, _tile(unread: true));
      expect(_rowColor(tester), BaraedaColors.light.accentPrimarySoft);

      await _pump(tester, _tile());
      expect(_rowColor(tester), Colors.transparent);
    });

    testWidgets('안 읽음은 제목이 굵고 읽음은 보통 굵기다', (tester) async {
      await _pump(tester, _tile(unread: true));
      final unreadWeight = _titleWeight(tester);
      await _pump(tester, _tile());
      final readWeight = _titleWeight(tester);

      expect(unreadWeight, BaraedaFontWeight.bold);
      expect(readWeight, BaraedaFontWeight.regular);
    });

    testWidgets('안 읽음 점은 안 읽은 행에만 있다', (tester) async {
      await _pump(tester, _tile(unread: true));
      expect(find.byKey(NotificationTile.unreadDotKey), findsOneWidget);

      await _pump(tester, _tile());
      expect(find.byKey(NotificationTile.unreadDotKey), findsNothing);
    });

    testWidgets('안 읽은 행의 아이콘 원은 꽉 찬 색, 읽은 행은 옅은 색이다', (tester) async {
      Color? circle() =>
          (tester
                      .widget<Container>(find.byKey(NotificationTile.glyphKey))
                      .decoration!
                  as BoxDecoration)
              .color;

      await _pump(tester, _tile(unread: true));
      expect(circle(), BaraedaColors.light.statusMoving);
      await _pump(tester, _tile());
      expect(circle(), BaraedaColors.light.statusMovingSoft);
    });
  });

  group('중요 통지', () {
    testWidgets('중요 표시와 왼쪽 막대는 중요한 행에만 있다', (tester) async {
      await _pump(tester, _tile(important: true));
      expect(find.text('중요'), findsOneWidget);
      expect(find.byKey(NotificationTile.importantBarKey), findsOneWidget);

      await _pump(tester, _tile());
      expect(find.text('중요'), findsNothing);
      expect(find.byKey(NotificationTile.importantBarKey), findsNothing);
    });
  });

  group('낭독', () {
    testWidgets('행 하나를 한 번에 읽는다 — 안 읽음 · 중요 · 종류 · 제목 · 본문 · 시각', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _tile(unread: true, important: true));

      expect(
        tester.getSemantics(find.byType(NotificationTile)).label,
        '안 읽음, 중요, 미승차, 미승차 안내, '
        '김철수 학생이 탄 버스가 승하차지 근처에 도착했습니다., 오전 8시 37분',
      );
      handle.dispose();
    });

    testWidgets('읽은 일반 행에는 안 읽음·중요가 붙지 않는다', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _tile(body: null));

      expect(
        tester.getSemantics(find.byType(NotificationTile)).label,
        '미승차, 미승차 안내, 오전 8시 37분',
      );
      handle.dispose();
    });

    testWidgets('누를 수 있으면 버튼 역할을 싣는다', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _tile(onTap: () {}));
      expect(
        tester.getSemantics(find.byType(NotificationTile)),
        matchesSemantics(
          hasTapAction: true,
          isButton: true,
          label:
              '미승차, 미승차 안내, '
              '김철수 학생이 탄 버스가 승하차지 근처에 도착했습니다., 오전 8시 37분',
        ),
      );
      handle.dispose();
    });
  });

  group('크기', () {
    testWidgets('본문이 없어도 행 높이는 누르는 영역 48 이상이다', (tester) async {
      await _pump(tester, _tile(body: null, onTap: () {}));
      expect(
        tester.getSize(find.byType(NotificationTile)).height,
        greaterThanOrEqualTo(BaraedaSpacing.tapMin),
      );
    });

    testWidgets('본문은 최대 2줄, 제목은 1줄이다', (tester) async {
      await _pump(tester, _tile(body: '아주 ' * 80));
      expect(tester.widget<Text>(find.text('미승차 안내')).maxLines, 1);
      expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .where((t) => (t.data ?? '').startsWith('아주'))
            .single
            .maxLines,
        2,
      );
    });

    testWidgets('눌렀을 때 onTap 이 불린다', (tester) async {
      var taps = 0;
      await _pump(tester, _tile(onTap: () => taps++));
      await tester.tap(find.byType(NotificationTile));
      expect(taps, 1);
    });
  });

  testWidgets('다크 테마에서도 안 읽음 바탕은 다크 색을 쓴다', (tester) async {
    await _pump(tester, _tile(unread: true), theme: BaraedaTheme.dark());
    expect(_rowColor(tester), BaraedaColors.dark.accentPrimarySoft);
  });
}
