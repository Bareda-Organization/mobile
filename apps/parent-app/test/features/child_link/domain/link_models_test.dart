import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/features/child_link/domain/link_models.dart';

/// §3.2~§3.4 응답 3종 파싱 시험.
void main() {
  test('LinkRequestResult.fromJson', () {
    final result = LinkRequestResult.fromJson({
      'link_request_id': 'lr-1',
      'expires_at': '2026-09-12T00:30:00Z',
    });

    expect(result.linkRequestId, 'lr-1');
    expect(result.expiresAt, DateTime.parse('2026-09-12T00:30:00Z'));
  });

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
