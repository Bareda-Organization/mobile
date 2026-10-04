// 앱이 Material `AlertDialog`·`showModalBottomSheet` 대신 쓰는 라우트형 공용판(Ruling 405).
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpHost(
    WidgetTester tester,
    Future<void> Function(BuildContext context) onOpen,
  ) => tester.pumpWidget(
    MaterialApp(
      theme: BaraedaTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => onOpen(context),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    ),
  );

  group('showBaraedaConfirmDialog', () {
    Future<bool?> open(WidgetTester tester, {bool dismissible = true}) async {
      bool? result;
      var done = false;
      await pumpHost(tester, (context) async {
        result = await showBaraedaConfirmDialog(
          context: context,
          title: '로그아웃',
          body: '로그아웃 하시겠습니까?',
          confirmLabel: '로그아웃하기',
          dismissible: dismissible,
        );
        done = true;
      });
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(find.text('로그아웃'), findsOneWidget);
      expect(find.text('로그아웃 하시겠습니까?'), findsOneWidget);
      // 호출부가 결과를 읽을 수 있게 완료 여부를 돌려준다.
      return done ? result : null;
    }

    testWidgets('확인 버튼은 true', (tester) async {
      bool? result;
      await pumpHost(tester, (context) async {
        result = await showBaraedaConfirmDialog(
          context: context,
          title: '삭제',
          confirmLabel: '삭제하기',
        );
      });
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제하기'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(find.text('삭제'), findsNothing);
    });

    testWidgets('취소 버튼은 false', (tester) async {
      bool? result;
      await pumpHost(tester, (context) async {
        result = await showBaraedaConfirmDialog(
          context: context,
          title: '삭제',
          confirmLabel: '삭제하기',
        );
      });
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('뒤로가기는 false 로 닫는다', (tester) async {
      bool? result;
      await pumpHost(tester, (context) async {
        result = await showBaraedaConfirmDialog(
          context: context,
          title: '삭제',
          confirmLabel: '삭제하기',
        );
      });
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(find.text('삭제'), findsNothing);
    });

    testWidgets('바깥을 누르면 false 로 닫는다', (tester) async {
      bool? result;
      await pumpHost(tester, (context) async {
        result = await showBaraedaConfirmDialog(
          context: context,
          title: '삭제',
          confirmLabel: '삭제하기',
        );
      });
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('dismissible: false 면 바깥·뒤로가기로 닫히지 않는다', (tester) async {
      await open(tester, dismissible: false);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('로그아웃'), findsOneWidget);
    });

    testWidgets('확인(위) · 취소(아래)가 세로로 쌓이고 폭이 같다(시안 대화상자 단추)', (tester) async {
      await pumpHost(
        tester,
        (context) => showBaraedaConfirmDialog(
          context: context,
          title: '안내',
          body: '본문',
          confirmLabel: '확인',
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      final cancel = tester.getRect(find.widgetWithText(BaraedaButton, '취소'));
      final confirm = tester.getRect(find.widgetWithText(BaraedaButton, '확인'));
      expect(confirm.bottom, lessThanOrEqualTo(cancel.top));
      expect(confirm.left, cancel.left);
      expect(confirm.width, cancel.width);
    });

    testWidgets('content 위젯을 본문으로 그린다', (tester) async {
      await pumpHost(
        tester,
        (context) => showBaraedaConfirmDialog(
          context: context,
          title: '안내',
          content: const Text('위젯 본문'),
          confirmLabel: '확인',
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(find.text('위젯 본문'), findsOneWidget);
    });
  });

  testWidgets('라우트로 띄운 본문은 Material 조상을 갖는다(칩·잉크·글자 서식)', (tester) async {
    await pumpHost(
      tester,
      (context) => showBaraedaBottomSheet<void>(
        context: context,
        builder: (_) => const Text('시트 내용'),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(Material.maybeOf(tester.element(find.text('시트 내용'))), isNotNull);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await pumpHost(
      tester,
      (context) => showBaraedaConfirmDialog(
        context: context,
        title: '안내',
        content: const Text('대화 내용'),
        confirmLabel: '확인',
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(Material.maybeOf(tester.element(find.text('대화 내용'))), isNotNull);
  });

  group('showBaraedaBottomSheet', () {
    testWidgets('builder 안에서 pop 한 값을 돌려준다', (tester) async {
      String? result;
      await pumpHost(tester, (context) async {
        result = await showBaraedaBottomSheet<String>(
          context: context,
          title: '연락 기록',
          builder: (sheetContext) => TextButton(
            onPressed: () => Navigator.of(sheetContext).pop('저장'),
            child: const Text('저장하기'),
          ),
        );
      });
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(find.text('연락 기록'), findsOneWidget);
      await tester.tap(find.text('저장하기'));
      await tester.pumpAndSettle();
      expect(result, '저장');
      expect(find.text('연락 기록'), findsNothing);
    });

    testWidgets('바깥·뒤로가기는 null 로 닫는다', (tester) async {
      var resolved = 0;
      String? result = 'x';
      await pumpHost(tester, (context) async {
        result = await showBaraedaBottomSheet<String>(
          context: context,
          title: '연락 기록',
          builder: (_) => const Text('내용'),
        );
        resolved++;
      });
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect((result, resolved), (null, 1));

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect((result, resolved), (null, 2));
    });
  });
}
