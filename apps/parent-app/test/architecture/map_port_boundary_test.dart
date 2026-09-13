import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 지도 SDK 를 화면이 직접 참조하지 못하게 막는 경계 검사.
///
/// **판단 근거** — `core/map/map_surface.dart` 문서가 요구하는 "SDK 타입은
/// `lib/core/map/naver/` 바깥에 절대 나타나지 않는다"를 사람이 리뷰마다
/// 눈으로 확인하는 대신 이 검사가 매번 자동으로 대신한다. 코드가 아니라
/// 텍스트를 훑는 검사라 컴파일 오류로는 못 잡는 것(예: 주석에만 남기고
/// 실제로는 안 쓰는 것과, 실제 import 문을 구분하지 못하는 상황)까지
/// 가르기 위해 주석을 걷어낸 본문에서만 판정한다
/// (`~/.claude/rules/phase-goal-loop.md §5.1` 과 같은 자리).
void main() {
  test('lib/core/map/naver/ 바깥에는 flutter_naver_map import 가 없다', () {
    final libDir = Directory('${Directory.current.path}/lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib 디렉터리를 찾을 수 없다');

    const forbidden = 'package:flutter_naver_map/';
    // 어댑터 폴더 안, 그리고 F4-B 0단계 탐침 전용 진입점(`probe_map_main.dart`,
    // "삭제·수정 금지" 대상)만 예외로 둔다. 경로 구분자를 `/` 로 정규화해
    // 비교한다(이 저장소는 macOS/Linux 에서만 돈다).
    const allowedDirSuffix = 'lib/core/map/naver';
    const allowedFile = 'probe_map_main.dart';

    final violations = <String>[];

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final normalized = entity.path.replaceAll(r'\', '/');
      final relative = normalized.substring(
        normalized.indexOf('/lib/') + 1,
      );
      final dirPart = normalized.substring(0, normalized.lastIndexOf('/'));
      final fileName = normalized.substring(normalized.lastIndexOf('/') + 1);

      if (dirPart.endsWith(allowedDirSuffix)) continue;
      if (fileName == allowedFile) continue;

      final withoutComments = _stripComments(entity.readAsStringSync());
      if (withoutComments.contains(forbidden)) {
        violations.add(relative);
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          '다음 파일이 어댑터 경계 밖에서 flutter_naver_map 을 직접 참조한다: '
          '${violations.join(', ')}',
    );
  });
}

/// `//` 한 줄 주석과 `/* */` 블록 주석을 제거한 본문을 돌려준다. 문자열
/// 리터럴 안의 `//`·`/*` 는 이 저장소의 실제 import 문 형태(항상 파일
/// 맨 위, 줄 시작)와 섞일 일이 없어 정교한 파서 없이 이 정도로 충분하다.
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
