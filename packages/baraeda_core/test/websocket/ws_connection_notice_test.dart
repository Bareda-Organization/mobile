import 'dart:io';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// R46-FIXCONN C-12·K-6 — 같은 끊김을 클라이언트마다 다른 문구로 알리지 않는다.
/// 웹(`academy-web`)과 두 앱이 같은 제목을 쓰며, 이 시험이 웹 파일의 제목과
/// 대조해 한쪽만 고치면 실패하게 한다(문구를 바꾸면 양쪽을 같이 고친다).
void main() {
  // 웹은 web 저장소에 있다(2026-10-02 저장소 분리). 이 시험은 패키지 루트(packages/baraeda_core)에서
  // 실행되므로 기본값은 형제 clone(`../web`)이고, CI 는 `WEB_REPO_DIR` 로 받는다. 파일이 없으면 실패한다.
  final webRepo = Platform.environment['WEB_REPO_DIR'] ?? '../../../web';
  final webFile = File('$webRepo/src/shared/lib/ws/wsConnectionNotice.ts');

  String webTitleOf(String constName) {
    final source = webFile.readAsStringSync();
    final match = RegExp(
      'const $constName: WsConnectionNotice = \\{\\s*title: "([^"]+)"',
    ).firstMatch(source);
    expect(match, isNotNull, reason: '웹 파일에서 $constName 의 제목을 못 찾았다');
    return match!.group(1)!;
  }

  test('연결 끊김 안내 제목 3종이 웹과 같다', () {
    expect(WsConnectionNotice.reconnectingTitle, webTitleOf('RECONNECTING'));
    expect(WsConnectionNotice.gaveUpTitle, webTitleOf('GAVE_UP'));
    expect(WsConnectionNotice.forbiddenTitle, webTitleOf('FORBIDDEN'));
  });

  test('세 제목은 서로 다르다 — 상태를 문구로 가를 수 있어야 한다', () {
    final titles = {
      WsConnectionNotice.reconnectingTitle,
      WsConnectionNotice.gaveUpTitle,
      WsConnectionNotice.forbiddenTitle,
    };
    expect(titles, hasLength(3));
  });
}
