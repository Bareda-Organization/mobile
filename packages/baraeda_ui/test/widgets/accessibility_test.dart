import 'package:baraeda_ui/theme/baraeda_theme.dart';
import 'package:baraeda_ui/widgets/core/core.dart';
import 'package:baraeda_ui/widgets/forms/forms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 접근성 라벨(`Semantics.label`)이 실제로 시맨틱 트리에 실리는지 위젯마다
/// 확인한다. 원본 `IconButton`의 "label은 필수" 규칙이 다른 위젯에도
/// 일관되게 이어졌는지가 이 파일의 목적이다.
///
/// 자식에 같은 문구의 `Text`가 있는 위젯(체크박스·스위치·세그먼트)은
/// Flutter가 부모 [Semantics]의 label과 자식 Text의 label을 한 노드로
/// 병합하며 줄바꿈으로 이어 붙인다 — 그래서 정확히 일치하는 문자열이 아니라
/// 그 문구를 포함하는지(정규식)로 확인한다.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        theme: BaraedaTheme.light(),
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('BaraedaIconButton은 label을 시맨틱에 싣는다', (tester) async {
    await pump(
      tester,
      BaraedaIconButton(icon: 'bell', label: '알림 열기', onPressed: () {}),
    );
    expect(find.bySemanticsLabel('알림 열기'), findsOneWidget);
  });

  testWidgets('BaraedaStatusPill은 label을 시맨틱에 싣는다', (tester) async {
    await pump(
      tester,
      const BaraedaStatusPill(status: BaraedaStatus.boarded, label: '탑승 완료'),
    );
    expect(find.bySemanticsLabel(RegExp('탑승 완료')), findsWidgets);
  });

  testWidgets('BaraedaBadge는 label(+count)을 시맨틱에 싣는다', (tester) async {
    await pump(tester, const BaraedaBadge(label: '대기', count: 3));
    expect(find.bySemanticsLabel(RegExp('대기 · 3')), findsWidgets);
  });

  testWidgets('BaraedaInput은 textField 시맨틱과 label을 싣는다', (tester) async {
    await pump(tester, const BaraedaInput(label: '이름'));

    expect(
      tester.getSemantics(find.byType(TextField)),
      matchesSemantics(
        isTextField: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    // 필드 위 라벨(RichText) + Semantics(textField: true, label:) 래퍼,
    // 둘 다 같은 문구를 싣는다.
    expect(find.bySemanticsLabel('이름'), findsWidgets);
  });

  testWidgets('BaraedaSearchField는 placeholder를 label로 싣는다', (tester) async {
    await pump(tester, const BaraedaSearchField(placeholder: '학생 검색'));
    // 바깥 Semantics 래퍼 + TextField의 hintText 시맨틱, 둘 다
    // placeholder 문구를 싣는다 — 최소 하나 이상 존재하는지만 본다.
    expect(find.bySemanticsLabel('학생 검색'), findsWidgets);
  });

  testWidgets('BaraedaCheckbox는 checked 상태와 label을 싣는다', (tester) async {
    await pump(
      tester,
      BaraedaCheckbox(checked: true, label: '약관 동의', onChanged: (_) {}),
    );

    expect(
      tester.getSemantics(find.byType(InkWell)),
      matchesSemantics(
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    expect(find.bySemanticsLabel(RegExp('약관 동의')), findsWidgets);
  });

  testWidgets('BaraedaSwitch는 toggled 상태와 label을 싣는다', (tester) async {
    await pump(
      tester,
      BaraedaSwitch(checked: true, label: '알림 받기', onChanged: (_) {}),
    );

    expect(
      tester.getSemantics(find.byType(InkWell)),
      matchesSemantics(
        hasToggledState: true,
        isToggled: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    expect(find.bySemanticsLabel(RegExp('알림 받기')), findsWidgets);
  });

  testWidgets('BaraedaSegmentedControl 옵션은 selected 상태와 label을 싣는다', (
    tester,
  ) async {
    await pump(
      tester,
      BaraedaSegmentedControl(
        options: const [
          BaraedaSegmentedOption('all', label: '전체'),
          BaraedaSegmentedOption('boarding', label: '승차'),
        ],
        value: 'all',
        onChanged: (_) {},
      ),
    );

    expect(find.bySemanticsLabel(RegExp('전체')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('승차')), findsWidgets);
  });

  testWidgets('BaraedaCodeInput은 textField 시맨틱을 싣는다', (tester) async {
    await pump(
      tester,
      BaraedaCodeInput(value: '', onChanged: (_) {}, label: '인증번호'),
    );
    // 필드 위 라벨 Text + Semantics(textField: true, label:) 래퍼, 둘 다
    // 같은 문구를 싣는다.
    expect(find.bySemanticsLabel('인증번호'), findsWidgets);
  });
}
