// `BaraedaDialog`·`BaraedaBottomSheet` 공용판의 결함 3종(F07-11 (3) · Ruling 405):
// ① 긴 본문·큰 글자에서 넘친다 ② 안드로이드 뒤로가기를 못 받는다 ③ 뒤의 화면을 낭독기가 계속 읽는다.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final longBody = List.generate(60, (i) => '본문 ${i + 1}줄').join('\n');

  Widget app(
    Widget Function(VoidCallback onClose) overlay, {
    List<Widget>? behind,
  }) {
    return MaterialApp(
      theme: BaraedaTheme.light(),
      home: Builder(
        builder: (context) => Stack(children: [...?behind, overlay(() {})]),
      ),
    );
  }

  void smallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('BaraedaDialog', () {
    testWidgets('긴 본문은 넘치지 않고 스크롤되며 버튼은 화면에 남는다', (tester) async {
      smallScreen(tester);
      var confirmed = false;
      await tester.pumpWidget(
        app(
          (_) => BaraedaDialog(
            title: '긴 안내',
            body: longBody,
            footer: BaraedaButton(
              label: '확인',
              onPressed: () => confirmed = true,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('본문 60줄', skipOffstage: false), findsNothing);

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -3000),
      );
      await tester.pump();
      expect(find.textContaining('본문 60줄'), findsOneWidget);

      await tester.tap(find.text('확인'));
      expect(confirmed, isTrue);
    });

    testWidgets('뒤로가기는 onClose 를 부르고 뒤 화면을 닫지 않는다', (tester) async {
      var closed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: BaraedaTheme.light(),
          home: Stack(
            children: [BaraedaDialog(title: '확인', onClose: () => closed++)],
          ),
        ),
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(closed, 1);
    });

    testWidgets('뒤 화면의 글자는 낭독 트리에서 빠진다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          (_) => const BaraedaDialog(title: '확인'),
          behind: const [Text('배경 글자')],
        ),
      );
      expect(find.bySemanticsLabel('배경 글자'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('확인')), findsOneWidget);
      handle.dispose();
    });
  });

  group('BaraedaBottomSheet', () {
    testWidgets('긴 내용은 넘치지 않고 스크롤된다', (tester) async {
      smallScreen(tester);
      await tester.pumpWidget(
        app((_) => BaraedaBottomSheet(title: '긴 시트', child: Text(longBody))),
      );
      expect(tester.takeException(), isNull);

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -3000),
      );
      await tester.pump();
      expect(find.textContaining('본문 60줄'), findsOneWidget);
    });

    testWidgets('키보드가 올라오면 시트가 그만큼 올라간다', (tester) async {
      smallScreen(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          theme: BaraedaTheme.light(),
          home: const Stack(
            children: [BaraedaBottomSheet(title: '입력', child: Text('내용'))],
          ),
        ),
      );
      final bottom = tester.getBottomLeft(find.text('내용')).dy;
      expect(bottom, lessThanOrEqualTo(600 - 300));
    });

    testWidgets('뒤로가기는 onClose 를 부른다', (tester) async {
      var closed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: BaraedaTheme.light(),
          home: Stack(
            children: [
              BaraedaBottomSheet(title: '시트', onClose: () => closed++),
            ],
          ),
        ),
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(closed, 1);
    });

    testWidgets('뒤 화면의 글자는 낭독 트리에서 빠진다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          (_) => const BaraedaBottomSheet(title: '시트'),
          behind: const [Text('배경 글자')],
        ),
      );
      expect(find.bySemanticsLabel('배경 글자'), findsNothing);
      handle.dispose();
    });
  });
}
