import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F4-B 1단계 공통 규칙 §2 — 지도 SDK(`flutter_naver_map`)를
/// `lib/core/map/naver/` 밖에서 직접 import 하면 이 검사가 실패한다.
/// 화면 코드는 `lib/core/map/map_surface.dart` 만 알아야 한다는 규칙이
/// 말로만 남지 않도록, `lib/` 전체를 훑어 금지된 import 를 센다.
void main() {
  test('lib/core/map/naver/ 밖에서 flutter_naver_map 을 import 하지 않는다', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ 디렉터리가 없다');

    const allowedPrefix = 'lib/core/map/naver/';
    final violations = <String>[];

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      // 경로 구분자를 '/' 로 통일 — 이 검사는 macOS·Linux 에서만 돈다.
      final relativePath = entity.path.replaceAll(r'\', '/');
      if (relativePath.startsWith(allowedPrefix)) continue;

      final content = entity.readAsStringSync();
      for (final line in content.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('//')) continue;
        if (trimmed.contains("import 'package:flutter_naver_map/") ||
            trimmed.contains('import "package:flutter_naver_map/')) {
          violations.add('$relativePath: $trimmed');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          '지도 SDK import 가 어댑터 밖으로 샜다(F4-B 공통 규칙 §2):\n'
          '${violations.join('\n')}',
    );
  });
}
