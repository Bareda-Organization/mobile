import 'dart:io';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// BR-301(Ruling 781) — `GET /auth/signup-status` 의 `academy_contact` 는 학원이 대표 연락처를
/// 등록하지 않았으면 키는 있고 값이 `null` 이다(API_SPEC §2.3). `as String` 으로 읽으면
/// 승인 대기 화면이 TypeError 로 실패한다.
Map<String, dynamic> _json({Object? contact}) => {
  'status': 'pending',
  'academy': {'name': '바래다학원', 'region': '서울', 'code': 'A-001'},
  'requested_at': '2026-09-01T00:00:00Z',
  'academy_contact': contact,
};

void main() {
  test('academy_contact 가 null 이어도 읽히고, 대체 문구를 돌려준다', () {
    final status = SignupStatusResponse.fromJson(_json());

    expect(status.academyContact, isNull);
    expect(
      status.academyContactText,
      SignupStatusResponse.noAcademyContactText,
    );
  });

  test('academy_contact 가 있으면 그 값을 그대로 돌려준다', () {
    final status = SignupStatusResponse.fromJson(_json(contact: '02-555-0101'));

    expect(status.academyContact, '02-555-0101');
    expect(status.academyContactText, '02-555-0101');
  });

  // 같은 안내를 클라이언트마다 다른 문구로 하지 않는다 — 웹 파일의 대체 문구와 대조한다.
  // 웹은 web 저장소에 있다. 이 시험은 패키지 루트에서 실행되므로 기본값은 형제 clone(`../web`)이고
  // CI 는 `WEB_REPO_DIR` 로 받는다. 파일이 없으면 실패한다.
  test('대체 문구가 웹 승인 대기 화면과 같다', () {
    final webRepo = Platform.environment['WEB_REPO_DIR'] ?? '../../../web';
    final source = File(
      '$webRepo/src/features/auth/components/SignupStatusPanel.tsx',
    ).readAsStringSync();
    final match = RegExp(r'academyContact \?\? "([^"]+)"').firstMatch(source);

    expect(match, isNotNull, reason: '웹 파일에서 학원 문의처 대체 문구를 못 찾았다');
    expect(SignupStatusResponse.noAcademyContactText, match!.group(1));
  });
}
