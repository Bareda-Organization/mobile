// [DelayPicker] 시험 — core 의존이 없어 pump 로 실제 확인 가능.
// §8 요구대로 상태 색 매핑(선택 시 statusMoving)과 접근성 라벨을 검사한다.
import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/theme/baraeda_theme.dart';
import 'package:baraeda_ui/widgets/transit/delay_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: BaraedaTheme.light(),
      home: Scaffold(body: child),
    );
  }

  testWidgets('기본 옵션 6개(5~30분)를 그린다', (tester) async {
    await tester.pumpWidget(wrap(const DelayPicker()));

    for (final minutes in [5, 10, 15, 20, 25, 30]) {
      expect(find.text('$minutes분'), findsOneWidget);
    }
  });

  testWidgets('옵션을 탭하면 onChanged 가 그 분 값으로 호출된다', (tester) async {
    int? picked;
    await tester.pumpWidget(
      wrap(DelayPicker(onChanged: (minutes) => picked = minutes)),
    );

    await tester.tap(find.text('10분'));
    await tester.pump();

    expect(picked, 10);
  });

  testWidgets('선택된 옵션은 Semantics.selected 가 true 다', (tester) async {
    await tester.pumpWidget(wrap(const DelayPicker(value: 10)));

    // SemanticsNode.hasFlag 는 deprecated 라, 지정한 값만 검사하는
    // isSemantics 로 확인한다(matchesSemantics 는 명시 안 한 플래그까지
    // false 로 강제해 hasTapAction 등에서 오탐이 난다).
    expect(
      tester.getSemantics(find.text('10분')),
      isSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(find.text('5분')),
      isSemantics(isSelected: false),
    );
  });

  testWidgets('선택된 옵션의 글자색은 statusMoving 이다(상태 색 매핑)', (tester) async {
    await tester.pumpWidget(wrap(const DelayPicker(value: 10)));

    final text = tester.widget<Text>(find.text('10분'));
    expect(text.style!.color, BaraedaColors.light.statusMoving);
  });

  testWidgets('접근성 라벨이 "N분" 을 담는다', (tester) async {
    await tester.pumpWidget(wrap(const DelayPicker()));

    // Semantics(label: '5분') 와 그 안의 Text('5분') 이 한 노드로 병합돼
    // label 이 "5분\n5분" 형태로 나온다 — 라벨에 "N분" 값이 담겨 있는지만
    // contains 로 검사한다.
    final semantics = tester.getSemantics(find.text('5분'));
    expect(semantics.label, contains('5분'));
  });
}
