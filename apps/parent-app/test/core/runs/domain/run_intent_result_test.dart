import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/runs/domain/run_intent_result.dart';

/// §3.6 파싱 시험 — `change_request_id` 는 서버(`BoardingIntentToggleResponse`,
/// `Long` 필드)가 따옴표 없는 JSON 정수로 돌려준다. `as String?` 직접 캐스트로
/// 되돌아가면 ② 구간(승인 대기) 응답을 파싱하는 순간 죽는다.
void main() {
  test(
    'RunIntentResult.fromJson 은 change_request_id 가 숫자로 와도 죽지 않는다',
    () {
      final result = RunIntentResult.fromJson({
        'result': 'pending_approval',
        'riding': false,
        'rider_status': 'waiting',
        'change_request_id': 8812,
        'change_quota_left': 1,
        'deadline_at': '2026-09-13T08:00:00Z',
      });

      expect(result.result, RunIntentApplyResult.pendingApproval);
      expect(result.changeRequestId, '8812');
    },
  );

  test('RunIntentResult.fromJson 은 change_request_id 부재 시 null 로 남긴다', () {
    final result = RunIntentResult.fromJson({
      'result': 'applied',
      'riding': true,
      'rider_status': 'boarded',
      'change_quota_left': 2,
    });

    expect(result.changeRequestId, isNull);
  });
}
