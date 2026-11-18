import 'dart:io';

import 'package:baraeda_core/widget_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// `CONVENTIONS_FLUTTER.md §5` — 이 패키지의 위젯도 200줄을 넘지 않고 `Widget _build…()` 도우미가 없다.
void main() {
  test('위젯이 200줄을 넘지 않고 Widget _build…() 도우미가 없다', () {
    final violations = widgetRuleViolations(Directory('lib'));

    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
