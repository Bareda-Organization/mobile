// [BaraedaBottomSheet] 시험 — core 의존이 없어 pump 로 실제 확인 가능.
import 'package:baraeda_ui/theme/baraeda_theme.dart';
import 'package:baraeda_ui/widgets/feedback/baraeda_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget sheet) {
    return MaterialApp(
      theme: BaraedaTheme.light(),
      home: Scaffold(body: Stack(children: [sheet])),
    );
  }

  testWidgets('title 과 child 를 그린다', (tester) async {
    await tester.pumpWidget(
      wrap(const BaraedaBottomSheet(title: '정류장 상세', child: Text('한화아파트 정류장'))),
    );

    expect(find.text('정류장 상세'), findsOneWidget);
    expect(find.text('한화아파트 정류장'), findsOneWidget);
  });

  testWidgets('title 이 Semantics 라우트 이름으로 노출된다', (tester) async {
    // bySemanticsLabel 로 찾으려면 시맨틱스 트리 생성을 먼저 켜야 한다.
    // addTearDown 은 flutter_test 의 종료 시점 검사보다 늦게 돌아서
    // "핸들이 안 닫혔다" 로 잡히므로, 여기서 직접 dispose 한다.
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(wrap(const BaraedaBottomSheet(title: '정류장 상세')));

    // 카드 내용을 감싸는 Semantics(namesRoute: true, label: title) 노드는
    // 안쪽 텍스트와 병합돼 라벨이 두 번 겹치는 형태가 된다(dialog 시험과
    // 같은 이유) — 정규식으로 라벨이 담겼는지만 확인한다.
    expect(find.bySemanticsLabel(RegExp('정류장 상세')), findsOneWidget);

    handle.dispose();
  });

  testWidgets('스크림을 탭하면 onClose 가 호출된다', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      wrap(BaraedaBottomSheet(title: '정류장 상세', onClose: () => closed = true)),
    );

    // 시트는 화면 하단에 붙으므로, 상단(스크림 영역)을 탭한다.
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();

    expect(closed, isTrue);
  });
}
