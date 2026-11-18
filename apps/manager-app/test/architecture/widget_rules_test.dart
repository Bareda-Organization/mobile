import 'dart:io';

import 'package:baraeda_core/widget_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// `CONVENTIONS_FLUTTER.md §5` — 위젯 하나는 200줄을 넘지 않고, `build` 안에서 함수로 위젯을
/// 쪼개지 않고 별도 위젯 클래스로 뺀다. 함수는 리빌드 범위를 좁히지 못해 목록 화면에서 전체가 다시 그려진다.
void main() {
  test('위젯이 200줄을 넘지 않고 Widget _build…() 도우미가 없다', () {
    final violations = widgetRuleViolations(Directory('lib'));

    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
