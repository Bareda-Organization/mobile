import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `features/<a>` 이 다른 기능 `features/<b>` 를 import 하지 못하게 막는 검사(F05-12).
///
/// **판단 근거** — 두 기능이 함께 쓰는 값은 `core/` 로 올리는 것이 이 앱의 규칙이다
/// (`CONVENTIONS_FLUTTER.md §2` "기능끼리 서로 import 하지 않음"). 한 기능이 다른 기능의 파일을
/// 물면 그 파일을 옮길 때 두 화면이 함께 깨진다.
void main() {
  test('features 안의 파일이 다른 feature 를 import 하지 않는다', () {
    final featuresDir = Directory('${Directory.current.path}/lib/features');
    expect(featuresDir.existsSync(), isTrue, reason: 'lib/features 를 찾을 수 없다');

    final importOfFeature = RegExp(
      r'''import\s+['"]package:parent_app/features/(\w+)/''',
    );
    final violations = <String>[];
    for (final entity in featuresDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final own = entity.path.split('/lib/features/')[1].split('/').first;
      for (final match in importOfFeature.allMatches(
        entity.readAsStringSync(),
      )) {
        if (match.group(1) != own) {
          violations.add('${entity.path.split('/lib/').last} → ${match[1]}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: '공유 값은 core/ 로 올릴 것: ${violations.join(', ')}',
    );
  });
}
