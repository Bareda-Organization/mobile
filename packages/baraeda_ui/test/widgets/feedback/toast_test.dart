// 토스트 — 220ms ease-out · 가벼운 성공 햅틱 1회(C7). 운행 중 다크 구역에서는 움직임 없음.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host extends StatelessWidget {
  const new({this.onAction, this.drive = false, this.bottomOffset});

  final VoidCallback? onAction;
  final bool drive;
  final double? bottomOffset;

  @override
  Widget build(BuildContext context) {
    final body = Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => showBaraedaToast(
            context,
            message: '새솔초 정문 도착 처리했어요 · 12:36',
            actionLabel: onAction == null ? null : '되돌리기',
            onAction: onAction,
            bottomOffset: bottomOffset,
          ),
          child: const Text('열기'),
        ),
      ),
    );
    return MaterialApp(
      theme: BaraedaTheme.light(),
      home: Scaffold(body: drive ? BaraedaDriveZone(child: body) : body),
    );
  }
}

void main() {
  late List<MethodCall> haptics;

  setUp(() {
    haptics = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  double opacity(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find.descendant(
          of: find.byType(BaraedaToast),
          matching: find.byType(FadeTransition),
        ),
      )
      .opacity
      .value;

  testWidgets('뜨는 데 220ms — 중간에는 반투명, 끝나면 불투명', (tester) async {
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('열기'));
    await tester.pump();
    expect(find.text('새솔초 정문 도착 처리했어요 · 12:36'), findsOneWidget);
    expect(opacity(tester), lessThan(1));

    await tester.pump(const Duration(milliseconds: 110));
    final mid = opacity(tester);
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));

    await tester.pump(const Duration(milliseconds: 110));
    expect(opacity(tester), 1);
    // 정리: 자동으로 사라질 때까지 흘린다.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('가벼운 성공 햅틱을 1회만 울린다', (tester) async {
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('열기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(haptics.length, 1);
    expect(haptics.single.arguments, 'HapticFeedbackType.lightImpact');
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('시간이 지나면 저절로 사라진다', (tester) async {
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('열기'));
    await tester.pump();
    expect(find.byType(BaraedaToast), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(BaraedaToast), findsNothing);
  });

  testWidgets('단추를 누르면 콜백이 불리고 토스트가 닫힌다', (tester) async {
    var undone = 0;
    await tester.pumpWidget(_Host(onAction: () => undone++));
    await tester.tap(find.text('열기'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('되돌리기'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(undone, 1);
    expect(find.byType(BaraedaToast), findsNothing);
  });

  testWidgets('낭독 영역(liveRegion)으로 읽힌다', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('열기'));
    await tester.pump(); // 토스트가 처음 그려지는 프레임
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('도착 처리했어요'))),
      matchesSemantics(label: '새솔초 정문 도착 처리했어요 · 12:36', isLiveRegion: true),
    );
    await tester.pump(const Duration(seconds: 6));
    handle.dispose();
  });

  testWidgets('운행 중 다크 구역에서는 움직임 없이 바로 뜬다', (tester) async {
    await tester.pumpWidget(const _Host(drive: true));
    await tester.tap(find.text('열기'));
    await tester.pump();
    expect(find.byType(BaraedaToast), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BaraedaToast),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('토스트 면은 어두운 잉크(라이트) · 다크 구역에서는 밝은 면', (tester) async {
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('열기'));
    await tester.pump(const Duration(milliseconds: 300));
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(BaraedaToast),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(
      (box.decoration as BoxDecoration).color,
      BaraedaColors.light.inkSurface,
    );
    await tester.pump(const Duration(seconds: 6));
  });

  // 운행 중 화면은 아래에 큰 단추 줄이 있어 토스트가 그 위로 떠야 한다 — 단추를 가리면 다음 누름을 가로챈다.
  testWidgets('bottomOffset 을 주면 그 높이에 뜨고, 안 주면 탭 막대 위 기본 자리다', (tester) async {
    await tester.pumpWidget(const _Host(drive: true));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final defaultBottom =
        screenHeight - tester.getBottomLeft(find.byType(BaraedaToast)).dy;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const _Host(drive: true, bottomOffset: 96));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    final raisedBottom =
        screenHeight - tester.getBottomLeft(find.byType(BaraedaToast)).dy;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // 기본은 탭 막대(64) + 간격(16) 위다.
    expect(defaultBottom, closeTo(80, 0.5));
    expect(raisedBottom, closeTo(96, 0.5));
  });
}
