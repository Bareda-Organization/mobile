import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 실시간 위치 연결 주소를 앱이 직접 조립하지 못하게 막는 검사.
///
/// **판단 근거** — 앱이 스킴을 `ws` 로 박아 두면 로컬(`http`)에서는 붙지만
/// 배포 서버(`https`)에서는 암호화되지 않은 `ws://` 로 붙으려다 막혀 지도에
/// 버스가 안 뜬다. 로컬 검사로는 드러나지 않는 결함이라, `https` → `wss`
/// 분기를 가진 공용 `wsUrlFromApiBaseUrl`(baraeda_core) 만 쓰게 강제한다.
void main() {
  test('lib 안에 ws 스킴을 직접 박는 코드가 없다', () {
    final libDir = Directory('${Directory.current.path}/lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib 디렉터리를 찾을 수 없다');

    final forbidden = RegExp(r'''scheme:\s*['"]wss?['"]''');
    final violations = <String>[
      for (final entity in libDir.listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            forbidden.hasMatch(_stripLineComments(entity.readAsStringSync())))
          entity.path.substring(entity.path.indexOf('/lib/') + 1),
    ];

    expect(
      violations,
      isEmpty,
      reason:
          '다음 파일이 ws 주소를 직접 조립한다 — wsUrlFromApiBaseUrl 을 쓸 것: '
          '${violations.join(', ')}',
    );
  });
}

/// `//` 한 줄 주석(문서 주석 포함)을 걷어낸 본문. 주석에 적힌 예시가
/// 검사에 걸리지 않게 한다.
String _stripLineComments(String source) => source
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i < 0 ? line : line.substring(0, i);
    })
    .join('\n');
