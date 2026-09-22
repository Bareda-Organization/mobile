import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/features/child_link/domain/link_models.dart';

/// §3.3·§3.4 응답 2종 파싱 시험(Ruling 324 — §3.2 연결 요청 단계 폐지로 3종→2종).
void main() {
  test('LinkCodeResult.fromJson', () {
    final result = LinkCodeResult.fromJson({
      'code': '482913',
      'expires_at': '2026-09-12T00:10:00Z',
    });

    expect(result.code, '482913');
  });

  test('LinkConfirmResult.fromJson', () {
    final result = LinkConfirmResult.fromJson({
      'student_id': '4',
      'name': '이하늘',
    });

    expect(result.studentId, '4');
    expect(result.name, '이하늘');
  });
}
