// [DevQuickLogin] 시험 — **릴리스 빌드에 새지 않는가**가 요점이다.
//
// 시드 비밀번호를 상수로 들고 있어서, 릴리스에 남으면 그 문자열과 계정 목록이 그대로 나간다.
// 편의 기능이지만 새는 쪽의 대가가 커서 검사를 붙인다.
//
// ⚠ `kReleaseMode` 는 컴파일 상수라 시험에서 바꿀 수 없다 — 시험은 항상 debug 로 돈다.
// 그래서 "릴리스에서 안 그린다" 는 **소스에 그 분기가 실재하는지**로 대신 잰다. 약한 검사이지만
// 분기를 지우는 변경은 잡는다.
import 'dart:io';

import 'package:baraeda_ui/theme/baraeda_theme.dart';
import 'package:baraeda_ui/widgets/dev/dev_quick_login.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: BaraedaTheme.light(),
    home: Scaffold(body: child),
  );

  testWidgets('계정 단추를 그리고, 누르면 아이디와 시드 비밀번호를 함께 넘긴다', (tester) async {
    final picked = <List<String>>[];
    await tester.pumpWidget(
      wrap(
        DevQuickLogin(
          accounts: const [DevAccount('학부모', 'parentA1')],
          onPick: (id, pw) => picked.add([id, pw]),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('dev-login-parentA1')));
    await tester.pump();

    // ⚠ 비밀번호까지 본다 — 아이디만 넘기면 호출부가 빈 비밀번호로 제출해
    // 로그인 시도 횟수만 축내고 원인이 안 보인다.
    expect(picked, [
      ['parentA1', 'password'],
    ]);
  });

  test('릴리스 빌드를 막는 분기가 소스에 실재한다', () {
    final source = File(
      'lib/widgets/dev/dev_quick_login.dart',
    ).readAsStringSync();
    expect(
      source.contains('if (kReleaseMode) return const SizedBox.shrink();'),
      isTrue,
      reason: '이 분기가 없으면 시드 비밀번호·계정 목록이 릴리스 빌드에 그대로 남는다',
    );
  });
}
