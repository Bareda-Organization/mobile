/// 시험 전용 — `CONVENTIONS_FLUTTER.md §5` 위젯 규칙을 소스에서 직접 센다. 제품 코드는 가져오지 않는다
/// (`baraeda_core.dart` 배럴에 넣지 않는다).
library;

import 'dart:io';

/// 위젯 한 개의 최대 줄 수 — 선언 줄부터 닫는 중괄호까지(주석 · 빈 줄 포함).
const widgetMaxLines = 200;

final _classStart = RegExp(r'^(?:abstract\s+|final\s+|base\s+)?class\s+(\w+)');

final _widgetBase = RegExp(
  r'\bextends\s+(?:(?:Stateless|Stateful|Consumer|ConsumerStateful)Widget\b'
  r'|(?:Consumer)?State\s*<)',
);

final _buildHelper = RegExp(r'\b(?:List<)?Widget\??>?\s+_build[A-Z]\w*\s*[(<]');

final _stringLiteral = RegExp(
  r'''(?:'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*")''',
);

/// [libDirectory] 아래 손으로 쓴 `.dart` 파일에서 위젯 규칙을 어긴 곳 — 없으면 빈 목록.
///
/// 어긴 곳은 `경로:줄 — 이유` 한 줄씩이다. 규칙은 둘이다.
/// - 위젯(`StatelessWidget` · `StatefulWidget` · `ConsumerWidget` ·
///   `ConsumerStatefulWidget` · 그 `State` · `ConsumerState`) 클래스 하나가
///   [widgetMaxLines] 줄을 넘지 않는다.
/// - `Widget _build…()` 도우미 메서드를 두지 않는다.
List<String> widgetRuleViolations(Directory libDirectory) {
  final violations = <String>[];
  final files = libDirectory
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (file) =>
            file.path.endsWith('.dart') &&
            !file.path.endsWith('.g.dart') &&
            !file.path.endsWith('.freezed.dart'),
      );
  for (final file in files) {
    final lines = file.readAsLinesSync();
    final name = file.path.split('/lib/').last;
    for (var i = 0; i < lines.length; i++) {
      if (_buildHelper.hasMatch(lines[i])) {
        violations.add('$name:${i + 1} — Widget _build…() 도우미 메서드');
      }
      final match = _classStart.firstMatch(lines[i]);
      if (match == null || !_widgetBase.hasMatch(_declaration(lines, i))) {
        continue;
      }
      final length = _classLength(lines, i);
      if (length > widgetMaxLines) {
        violations.add(
          '$name:${i + 1} — ${match.group(1)} $length줄 '
          '(최대 $widgetMaxLines)',
        );
      }
    }
  }
  return violations;
}

/// [start] 줄에서 시작한 클래스의 선언부 — 여는 중괄호가 나오는 줄까지(두 줄 이상에 걸쳐 쓴 선언 포함).
String _declaration(List<String> lines, int start) {
  final buffer = StringBuffer();
  for (var i = start; i < lines.length; i++) {
    buffer.write('${lines[i]} ');
    if (lines[i].contains('{')) break;
  }
  return buffer.toString();
}

/// [start] 줄에서 시작한 클래스가 닫히는 줄까지의 줄 수 — 문자열 속 중괄호는 세지 않는다.
int _classLength(List<String> lines, int start) {
  var depth = 0;
  var opened = false;
  for (var i = start; i < lines.length; i++) {
    for (final char in lines[i].replaceAll(_stringLiteral, "''").split('')) {
      if (char == '{') {
        depth++;
        opened = true;
      } else if (char == '}') {
        depth--;
      }
    }
    if (opened && depth <= 0) return i - start + 1;
  }
  return lines.length - start;
}
