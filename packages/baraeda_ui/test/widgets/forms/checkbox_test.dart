import 'package:baraeda_ui/theme/baraeda_theme.dart';
import 'package:baraeda_ui/widgets/forms/forms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [BaraedaCheckbox]의 비활성 상태가 실제로 다르게 렌더링되는지 확인한다.
void main() {
  Future<double> opacityFor(
    WidgetTester tester, {
    required bool disabled,
    ValueChanged<bool>? onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BaraedaTheme.light(),
        home: Scaffold(
          body: BaraedaCheckbox(
            checked: false,
            label: '약관에 동의합니다',
            disabled: disabled,
            onChanged: onChanged,
          ),
        ),
      ),
    );
    final opacity = tester.widget<Opacity>(find.byType(Opacity));
    return opacity.opacity;
  }

  testWidgets('disabled: true이면 opacity 0.42로 렌더링된다', (tester) async {
    final opacity = await opacityFor(tester, disabled: true, onChanged: (_) {});
    expect(opacity, 0.42);
  });

  testWidgets('onChanged가 null이면 disabled 플래그와 무관하게 비활성이다', (tester) async {
    final opacity = await opacityFor(tester, disabled: false);
    expect(opacity, 0.42);
  });

  testWidgets('활성 상태(onChanged 존재 · disabled: false)는 opacity 1이다', (
    tester,
  ) async {
    final opacity = await opacityFor(
      tester,
      disabled: false,
      onChanged: (_) {},
    );
    expect(opacity, 1);
  });

  testWidgets('비활성 상태에서는 탭해도 onChanged가 호출되지 않는다', (tester) async {
    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: BaraedaTheme.light(),
        home: Scaffold(
          body: BaraedaCheckbox(
            checked: false,
            label: '약관에 동의합니다',
            disabled: true,
            onChanged: (_) => called = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pump();
    expect(called, isFalse);
  });
}
