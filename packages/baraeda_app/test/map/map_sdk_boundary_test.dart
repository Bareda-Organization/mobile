import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 지도 SDK(`flutter_naver_map`)는 `packages/baraeda_app/lib/map/naver/` 밖에서
/// import 하지 않는다.
///
/// 화면은 `map_surface.dart` 만 알고, SDK 타입(`NaverMap` · `NMarker` · `NLatLng`)은 어댑터
/// 폴더 안에만 둔다는 규칙이
/// 말로만 남지 않도록, 두 앱과 모든 공용 패키지의 `lib/` 를 훑어 금지된 import 를 센다. 주석을 걷어낸 본문에서만
/// 판정해 주석에 남은 이름과 실제 import 문을 구분한다.
void main() {
  test('flutter_naver_map import 는 공용 어댑터 폴더 안에만 있다', () {
    // 이 시험은 packages/baraeda_app 에서 돈다 — 저장소 루트는 두 단계 위다.
    final root = Directory('${Directory.current.path}/../..').absolute.path;
    const forbidden = 'package:flutter_naver_map/';
    const allowedDir = 'packages/baraeda_app/lib/map/naver/';

    var scanned = 0;
    var allowedUses = 0;
    final violations = <String>[];

    for (final group in ['packages', 'apps']) {
      for (final module in Directory('$root/$group').listSync()) {
        final lib = Directory('${module.path}/lib');
        if (!lib.existsSync()) continue;
        for (final entity in lib.listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          scanned++;
          final relative = entity.path.substring(root.length + 1);
          final usesSdk = _stripComments(entity.readAsStringSync())
              .contains(forbidden);
          if (!usesSdk) continue;
          if (relative.startsWith(allowedDir)) {
            allowedUses++;
          } else {
            violations.add(relative);
          }
        }
      }
    }

    expect(scanned, greaterThan(100), reason: '훑은 파일이 너무 적다 — 루트 경로 오류');
    expect(
      allowedUses,
      greaterThan(0),
      reason: '어댑터가 SDK 를 import 하지 않는다 — 검사가 아무것도 못 센다',
    );
    expect(
      violations,
      isEmpty,
      reason:
          '다음 파일이 어댑터 폴더 밖에서 flutter_naver_map 을 직접 참조한다: '
          '${violations.join(', ')}',
    );
  });
}

/// `//` 한 줄 주석과 `/* */` 블록 주석을 제거한 본문. 문자열 안의 `//` 는 이 저장소의 import 문과 섞일 일이 없어
/// 정교한 파서 없이 이 정도로 충분하다.
String _stripComments(String source) {
  final withoutBlockComments = source.replaceAll(
    RegExp(r'/\*.*?\*/', dotAll: true),
    '',
  );
  final buffer = StringBuffer();
  for (final line in withoutBlockComments.split('\n')) {
    final commentIndex = line.indexOf('//');
    buffer.writeln(commentIndex == -1 ? line : line.substring(0, commentIndex));
  }
  return buffer.toString();
}
