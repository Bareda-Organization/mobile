import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 공개 위젯마다 앱(`apps/*/lib`)에 쓰는 곳이 1곳 이상 있는지 본다(Ruling 405 · 903 G) —
/// 앱이 안 쓰는 위젯은 쌓이기만 하고 아무도 점검하지 않는다.
///
/// 쓰는 곳으로 치는 것 — ① 앱 lib 코드에 클래스 이름이 있다 ② 같은 파일의 `show*` 도움 함수를
/// 앱이 부른다(대화상자 · 시트 · 토스트) ③ 앱이 쓰는 다른 공개 위젯의 부품으로 들어간다.
void main() {
  test('baraeda_ui 의 공개 위젯은 앱 lib 에서 모두 쓰인다', () {
    final appCode = _codeOf(_dartFiles('../../apps').where(_isAppLib));
    final widgetFiles = _dartFiles('lib/widgets').toList();
    final fileCode = {
      for (final f in widgetFiles) f.path: _codeOf([f]),
    };

    final widgets = <String, File>{}; // 위젯 이름 → 선언 파일
    for (final file in widgetFiles) {
      for (final match in _widgetClass.allMatches(fileCode[file.path]!)) {
        widgets[match.group(1)!] = file;
      }
    }
    expect(widgets, isNotEmpty, reason: '공개 위젯을 한 개도 못 찾았다 — 정규식이 깨졌나');

    bool mentions(String code, String name) =>
        RegExp('\\b$name\\b').hasMatch(code);

    final used = <String>{};
    for (final entry in widgets.entries) {
      final helpers = _showHelper
          .allMatches(fileCode[entry.value.path]!)
          .map((m) => m.group(1)!);
      if ([entry.key, ...helpers].any((n) => mentions(appCode, n))) {
        used.add(entry.key);
      }
    }
    // 앱이 쓰는 위젯의 부품으로 들어가는 위젯도 쓰이는 것이다 — 더 늘지 않을 때까지 되풀이.
    // 부품으로 치는 언급은 그 위젯 자신의 클래스 본문 밖의 것이다 — 자기 선언 · 생성자 줄은 센다고 쓰이는 게 아니다.
    bool isPartOf(String user, String name) {
      final code = fileCode[widgets[user]!.path]!;
      final declaration = RegExp('class\\s+$name\\b').firstMatch(code);
      var outside = code;
      if (declaration != null) {
        final open = code.indexOf('{', declaration.start);
        var depth = 0;
        var end = open;
        for (; end < code.length; end++) {
          if (code[end] == '{') depth++;
          if (code[end] == '}' && --depth == 0) break;
        }
        outside = code.substring(0, declaration.start) + code.substring(end);
      }
      return mentions(outside, name);
    }

    var grew = true;
    while (grew) {
      grew = false;
      for (final name in widgets.keys.where((n) => !used.contains(n))) {
        if (used.any((user) => isPartOf(user, name))) {
          used.add(name);
          grew = true;
        }
      }
    }

    final unused = widgets.keys.where((n) => !used.contains(n)).toList()
      ..sort();
    expect(
      unused,
      isEmpty,
      reason: '앱(apps/*/lib)이 안 쓰는 공개 위젯: $unused — 지우거나 앱에서 쓴다',
    );
  });
}

final RegExp _widgetClass = RegExp(
  r'^(?:(?:abstract|final|base)\s+)*class\s+([A-Z]\w*)[^{;]*?\bextends\s+'
  r'(?:Stateless|Stateful|Inherited)Widget\b',
  multiLine: true,
);

final RegExp _showHelper = RegExp(
  r'^[\w<>?]+\s+(show[A-Z]\w*)\s*(?:<[^>]*>)?\(',
  multiLine: true,
);

bool _isAppLib(File file) =>
    file.path.contains('/lib/') && file.path.contains('/apps/');

Iterable<File> _dartFiles(String dir) =>
    Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

/// 줄 주석을 뺀 코드 — 주석에 적힌 이름이 사용처로 세어지지 않게 한다.
String _codeOf(Iterable<File> files) => files
    .map((f) => f.readAsLinesSync().map((l) => l.split('//').first).join('\n'))
    .join('\n');
