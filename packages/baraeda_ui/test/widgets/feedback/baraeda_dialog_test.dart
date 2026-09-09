// [BaraedaDialog] 시험 — core 패키지(BaraedaIcon·StatusPill) 의존이 없어
// 실제로 pump 해서 확인할 수 있다.
import 'package:baraeda_ui/theme/baraeda_theme.dart';
import 'package:baraeda_ui/widgets/feedback/baraeda_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget dialog) {
    return MaterialApp(
      theme: BaraedaTheme.light(),
      home: Scaffold(body: Stack(children: [dialog])),
    );
  }

  testWidgets('제목·본문을 그대로 그린다', (tester) async {
    await tester.pumpWidget(
      wrap(const BaraedaDialog(title: '정말 삭제할까요', body: '되돌릴 수 없습니다.')),
    );

    expect(find.text('정말 삭제할까요'), findsOneWidget);
    expect(find.text('되돌릴 수 없습니다.'), findsOneWidget);
  });

  testWidgets('title 이 Semantics 라우트 이름으로 노출된다', (tester) async {
    // bySemanticsLabel 로 찾으려면 시맨틱스 트리 생성을 먼저 켜야 한다.
    // addTearDown 은 flutter_test 의 종료 시점 검사보다 늦게 돌아서
    // "핸들이 안 닫혔다" 로 잡히므로, 여기서 직접 dispose 한다.
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(wrap(const BaraedaDialog(title: '정말 삭제할까요')));

    // 카드 내용을 감싸는 Semantics(namesRoute: true, label: title) 노드는
    // 안쪽 Text(title) 과 병합돼 라벨이 "정말 삭제할까요\n정말 삭제할까요"
    // 형태가 된다 — 정규식으로 라벨이 담겼는지만 확인한다.
    expect(find.bySemanticsLabel(RegExp('정말 삭제할까요')), findsOneWidget);

    handle.dispose();
  });

  testWidgets('스크림(바깥)을 탭하면 onClose 가 호출된다', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      wrap(BaraedaDialog(title: '확인', onClose: () => closed = true)),
    );

    // 카드 바깥, 화면 좌상단 모서리를 탭해 스크림을 누른다.
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();

    expect(closed, isTrue);
  });

  testWidgets('카드 안쪽을 탭해도 onClose 는 전파되지 않는다', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      wrap(
        BaraedaDialog(title: '확인', body: '본문', onClose: () => closed = true),
      ),
    );

    await tester.tap(find.text('본문'));
    await tester.pump();

    expect(closed, isFalse);
  });
}
