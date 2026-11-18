import 'dart:io';

import 'package:baraeda_core/widget_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// 위젯 규칙 검사기 자체의 시험 — 어긴 코드를 넣으면 잡고, 지킨 코드는 통과시킨다.
void main() {
  late Directory lib;

  setUp(() => lib = Directory.systemTemp.createTempSync('widget_rules_lib'));
  tearDown(() => lib.deleteSync(recursive: true));

  void write(String name, String source) => File('${lib.path}/lib/$name')
    ..createSync(recursive: true)
    ..writeAsStringSync(source);

  List<String> check() => widgetRuleViolations(Directory('${lib.path}/lib'));

  String widgetOf(int bodyLines, {String base = 'StatelessWidget'}) =>
      'class Big extends $base {\n${'  // line\n' * bodyLines}}\n';

  test('200줄 위젯은 통과하고 201줄 위젯은 잡는다', () {
    write('ok.dart', widgetOf(198));
    expect(check(), isEmpty);

    write('big.dart', widgetOf(199));
    expect(check().single, contains('big.dart:1'));
    expect(check().single, contains('201줄'));
  });

  test('State · ConsumerState 클래스도 위젯으로 센다', () {
    write('s.dart', widgetOf(250, base: 'State<Foo>'));
    write('c.dart', widgetOf(250, base: 'ConsumerState<Foo>'));

    expect(check(), hasLength(2));
  });

  test('위젯이 아닌 긴 클래스와 문자열 속 중괄호는 세지 않는다', () {
    write('model.dart', 'class Model {\n${'  // line\n' * 300}}\n');
    write(
      'brace.dart',
      "class Small extends StatelessWidget {\n  final a = '{';\n}\n",
    );

    expect(check(), isEmpty);
  });

  test('Widget _build…() 도우미 메서드를 잡는다', () {
    write(
      'helper.dart',
      'class A extends StatelessWidget {\n'
          '  Widget _buildBody() => const SizedBox();\n'
          '  List<Widget> _buildRows() => [];\n'
          '}\n',
    );

    expect(check(), hasLength(2));
    expect(check().first, contains('helper.dart:2'));
  });

  test('생성 파일은 보지 않는다', () {
    write('x.g.dart', widgetOf(400));

    expect(check(), isEmpty);
  });

  test('두 줄에 걸쳐 선언한 위젯도 잡는다', () {
    write(
      'wrapped.dart',
      'class _VeryLongWidgetNameState<T>\n'
      '    extends ConsumerState<VeryLongWidgetName<T>> {\n'
      '${'  // line\n' * 250}}\n',
    );

    expect(check().single, contains('wrapped.dart:1'));
    expect(check().single, contains('_VeryLongWidgetNameState'));
  });

  test('두 줄에 걸쳐 선언한 위젯이 200줄 이하면 통과한다', () {
    write(
      'wrapped_ok.dart',
      'class Small\n    extends StatelessWidget {\n${'  // line\n' * 100}}\n',
    );

    expect(check(), isEmpty);
  });
}
