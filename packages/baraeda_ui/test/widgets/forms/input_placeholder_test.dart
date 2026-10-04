// 입력 칸 안내 글자(placeholder) — 칸 안에 흐리게 보이는 입력 예시다. 칸 아래 보조 설명(hint)과 별개로 둘 다 보인다.
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
  testWidgets('placeholder 는 칸 안에, hint 는 칸 아래에 따로 그려진다', (tester) async {
    await tester.pumpWidget(
      _host(
        const BaraedaInput(
          label: '이름',
          placeholder: '실명을 입력해 주세요',
          hint: '주민등록상 이름',
        ),
      ),
    );

    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
      '실명을 입력해 주세요',
    );
    expect(find.text('주민등록상 이름'), findsOneWidget);
  });

  testWidgets('placeholder 를 안 주면 칸 안에 아무 글자도 없다', (tester) async {
    await tester.pumpWidget(_host(const BaraedaInput(label: '이름')));

    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
      isNull,
    );
  });
}
