// 입력 칸 속성(C4) — 종류마다 자동 완성 · 자판 · 철자 교정이 다르다. 높이 52 · 오류는 경고 아이콘 + 2px 테두리.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: BaraedaTheme.light(),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

void main() {
  testWidgets('아이디: username 자동 완성 · 철자 교정과 단어 추천 끔', (tester) async {
    await tester.pumpWidget(
      _host(const BaraedaInput(kind: BaraedaInputKind.username)),
    );
    final f = _field(tester);
    expect(f.autofillHints, [AutofillHints.username]);
    expect(f.autocorrect, isFalse);
    expect(f.enableSuggestions, isFalse);
  });

  testWidgets('비밀번호: 로그인은 password · 새 비밀번호는 newPassword', (tester) async {
    await tester.pumpWidget(
      _host(
        const BaraedaInput(
          kind: BaraedaInputKind.currentPassword,
          obscureText: true,
        ),
      ),
    );
    expect(_field(tester).autofillHints, [AutofillHints.password]);
    await tester.pumpWidget(
      _host(
        const BaraedaInput(
          kind: BaraedaInputKind.newPassword,
          obscureText: true,
        ),
      ),
    );
    expect(_field(tester).autofillHints, [AutofillHints.newPassword]);
  });

  testWidgets('연락처: 전화 자판 + telephoneNumber', (tester) async {
    await tester.pumpWidget(
      _host(const BaraedaInput(kind: BaraedaInputKind.phone)),
    );
    expect(_field(tester).keyboardType, TextInputType.phone);
    expect(_field(tester).autofillHints, [AutofillHints.telephoneNumber]);
  });

  testWidgets('인증번호: 숫자 자판 + oneTimeCode', (tester) async {
    await tester.pumpWidget(
      _host(const BaraedaInput(kind: BaraedaInputKind.oneTimeCode)),
    );
    expect(_field(tester).keyboardType, TextInputType.number);
    expect(_field(tester).autofillHints, [AutofillHints.oneTimeCode]);
  });

  testWidgets('keyboardType 을 따로 주면 종류의 자판보다 우선한다', (tester) async {
    await tester.pumpWidget(
      _host(
        const BaraedaInput(
          kind: BaraedaInputKind.phone,
          keyboardType: TextInputType.text,
        ),
      ),
    );
    expect(_field(tester).keyboardType, TextInputType.text);
  });

  testWidgets('일반 칸은 기본값 그대로(자동 완성 없음 · 교정 켜짐)', (tester) async {
    await tester.pumpWidget(_host(const BaraedaInput()));
    expect(_field(tester).autofillHints, isNull);
    expect(_field(tester).autocorrect, isTrue);
  });

  testWidgets('높이는 52 이상', (tester) async {
    await tester.pumpWidget(_host(const BaraedaInput(hint: '아이디를 입력하세요')));
    expect(
      tester.getSize(find.byType(TextField)).height,
      greaterThanOrEqualTo(BaraedaSpacing.inputHeight),
    );
  });

  testWidgets('오류는 경고 아이콘 + 글자, 테두리는 위험 면 색 2px', (tester) async {
    await tester.pumpWidget(
      _host(const BaraedaInput(label: '비밀번호', error: '비밀번호가 올바르지 않아요')),
    );
    expect(find.text('비밀번호가 올바르지 않아요'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    final border =
        _field(tester).decoration!.enabledBorder! as OutlineInputBorder;
    expect(border.borderSide.color, BaraedaColors.light.dangerSolid);
    expect(border.borderSide.width, 2);
  });
}
