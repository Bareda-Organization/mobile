// 숫자 전용 코드 칸 — 문자로 오는 인증번호는 숫자 자판이 뜨고 영문자는 걸러진다.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: BaraedaTheme.light(),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

void main() {
  testWidgets('numeric 이면 숫자 자판이 뜨고 영문자는 입력되지 않는다', (tester) async {
    var value = '';
    await tester.pumpWidget(
      _host(
        BaraedaCodeInput(
          value: '',
          numeric: true,
          onChanged: (next) => value = next,
        ),
      ),
    );

    expect(
      tester.widget<TextField>(find.byType(TextField)).keyboardType,
      TextInputType.number,
    );
    await tester.enterText(find.byType(TextField), '5a1b7');
    expect(value, '517');
  });

  testWidgets('numeric 이 아니면 영문 · 숫자를 받고 대문자로 바꾼다', (tester) async {
    var value = '';
    await tester.pumpWidget(
      _host(BaraedaCodeInput(value: '', onChanged: (next) => value = next)),
    );

    await tester.enterText(find.byType(TextField), 'a1b!');
    expect(value, 'A1B');
  });
}
