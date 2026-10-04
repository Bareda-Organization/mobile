// 연결 끊김 · 오프라인 띠 · 알림 띠 4종 · 빈 상태 · 시트(시안 kit).
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? BaraedaTheme.light(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Color _fill(WidgetTester tester, Finder within) =>
    ((tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: within,
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration)
            as BoxDecoration)
        .color!;

void main() {
  const colors = BaraedaColors.light;

  group('연결 띠', () {
    testWidgets('끊김은 어두운 잉크 면 · 높이 40 이상 · 알림 영역으로 읽힌다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const BaraedaConnectionStrip(
            state: BaraedaConnectionState.offline,
            message: '연결이 끊겼어요 · 처리 대기 2건',
          ),
        ),
      );
      final strip = find.byType(BaraedaConnectionStrip);
      expect(_fill(tester, strip), colors.inkSurface);
      expect(tester.getSize(strip).height, greaterThanOrEqualTo(40));
      expect(find.bySemanticsLabel('연결이 끊겼어요 · 처리 대기 2건'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('다시 연결하는 중은 앰버 · 복구는 초록', (tester) async {
      await tester.pumpWidget(
        _host(
          const Column(
            children: [
              BaraedaConnectionStrip(
                state: BaraedaConnectionState.reconnecting,
                message: '다시 연결하는 중…',
              ),
              BaraedaConnectionStrip(
                state: BaraedaConnectionState.restored,
                message: '다시 연결됐어요 · 2건 보냈어요',
              ),
            ],
          ),
        ),
      );
      final strips = find.byType(BaraedaConnectionStrip);
      expect(_fill(tester, strips.at(0)), colors.statusMovingSoft);
      expect(_fill(tester, strips.at(1)), colors.statusBoardedSoft);
    });

    testWidgets('다크 구역에서는 끊김 띠가 밝은 면으로 뒤집힌다', (tester) async {
      await tester.pumpWidget(
        _host(
          const BaraedaConnectionStrip(
            state: BaraedaConnectionState.offline,
            message: '연결이 끊겼어요',
          ),
          theme: BaraedaTheme.dark(),
        ),
      );
      expect(
        _fill(tester, find.byType(BaraedaConnectionStrip)),
        BaraedaColors.dark.inkSurface,
      );
      expect(BaraedaColors.dark.inkSurface, const Color(0xFFEDF2EF));
    });
  });

  group('알림 띠 4종', () {
    testWidgets('안내=옅은 초록(대기) · 이동 중=앰버 + 테두리 · 완료=초록 · 위험=빨강', (tester) async {
      await tester.pumpWidget(
        _host(
          const Column(
            children: [
              AlertBanner(tone: AlertTone.info, title: '확정 전'),
              AlertBanner(tone: AlertTone.moving, title: '버스가 10분 늦어요'),
              AlertBanner(tone: AlertTone.boarded, title: '탑승 처리됐어요'),
              AlertBanner(tone: AlertTone.missed, title: '보내지 못했어요'),
            ],
          ),
        ),
      );
      final banners = find.byType(AlertBanner);
      expect(_fill(tester, banners.at(0)), colors.statusWaitSoft);
      expect(_fill(tester, banners.at(1)), colors.statusMovingSoft);
      expect(_fill(tester, banners.at(2)), colors.statusBoardedSoft);
      expect(_fill(tester, banners.at(3)), colors.statusMissedSoft);
      final moving =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: banners.at(1),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect((moving.border! as Border).top.color, colors.shapeMoving);
    });

    testWidgets('inlineAction 이면 단추가 글 오른쪽 끝에 온다', (tester) async {
      await tester.pumpWidget(
        _host(
          AlertBanner(
            tone: AlertTone.missed,
            title: '보내지 못했어요',
            inlineAction: true,
            action: BaraedaButton(
              label: '다시 시도',
              size: BaraedaButtonSize.sm,
              onPressed: () {},
            ),
          ),
        ),
      );
      final title = tester.getRect(find.text('보내지 못했어요'));
      final action = tester.getRect(find.byType(BaraedaButton));
      expect(action.left, greaterThan(title.right));
      expect(action.center.dy, closeTo(title.center.dy, 12));
    });
  });

  group('빈 상태', () {
    testWidgets('아이콘 원 64 · 제목 20 · 본문 16 · 다음 행동 단추', (tester) async {
      await tester.pumpWidget(
        _host(
          EmptyState(
            title: '오늘 배정된 운행이 없어요',
            body: '배정되면 여기에 나타나요',
            action: BaraedaButton(label: '새로고침', onPressed: () {}),
          ),
        ),
      );
      expect(
        tester.widget<Text>(find.text('오늘 배정된 운행이 없어요')).style!.fontSize,
        20,
      );
      expect(
        tester.widget<Text>(find.text('배정되면 여기에 나타나요')).style!.fontSize,
        16,
      );
      final circle = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle,
      );
      expect(tester.getSize(circle.first), const Size(64, 64));
      expect(find.text('새로고침'), findsOneWidget);
    });
  });

  group('하단 시트', () {
    testWidgets('showCloseButton 이면 제목 줄에 닫기(X) 단추가 있다', (tester) async {
      var closed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: BaraedaTheme.light(),
          home: Scaffold(
            body: Stack(
              children: [
                BaraedaBottomSheet(
                  title: '도착 처리',
                  showCloseButton: true,
                  onClose: () => closed++,
                  child: const Text('되돌릴 수 없어요'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(
        find.byTooltip('닫기').evaluate().isNotEmpty
            ? find.byTooltip('닫기')
            : find.bySemanticsLabel('닫기'),
      );
      expect(closed, 1);
    });

    testWidgets('열릴 때 240ms 서랍 곡선으로 올라온다(entrance)', (tester) async {
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: BaraedaDuration.sheet,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: BaraedaTheme.light(),
          home: Scaffold(
            body: Stack(
              children: [
                BaraedaBottomSheet(
                  title: '시트',
                  entrance: controller,
                  motion: BaraedaOpenMotion.full,
                  child: const Text('내용'),
                ),
              ],
            ),
          ),
        ),
      );
      final slide = tester.widget<SlideTransition>(
        find.descendant(
          of: find.byType(BaraedaBottomSheet),
          matching: find.byType(SlideTransition),
        ),
      );
      expect(slide.position.value.dy, 1); // 시작: 화면 아래 밖
      controller.value = 1;
      await tester.pump();
      expect(slide.position.value.dy, 0); // 끝: 제자리
    });
  });

  testWidgets('AlertBanner 는 icon 을 주면 그 아이콘을, 안 주면 톤의 기본 아이콘을 그린다', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BaraedaTheme.light(),
        home: const Scaffold(
          body: Column(
            children: [
              AlertBanner(tone: AlertTone.moving, title: '기본'),
              AlertBanner(tone: AlertTone.moving, icon: 'route', title: '노선'),
            ],
          ),
        ),
      ),
    );

    final icons = tester
        .widgetList<BaraedaIcon>(find.byType(BaraedaIcon))
        .map((icon) => icon.name)
        .toList();
    expect(icons, ['bus', 'route']);
  });
}
