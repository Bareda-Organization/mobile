import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/roster/data/models/rider_update_result.dart';

/// M2(BR-054, Ruling 332) — §4.6 응답 `no_show_case.case_id` 를 서버가
/// 아직 숫자로 보내는데(`RiderStatusUpdateResponse.java` `Long caseId`)
/// `NoShowCase.fromJson` 이 `as String` 으로 직접 캐스트해 [미승차] 응답
/// 파싱이 형변환 예외로 죽는다 — `rider_id`(같은 파일)와 같은 방식으로
/// `asIdString` 흡수가 필요하다.
void main() {
  Map<String, dynamic> response({required Object caseId}) => {
    'rider_id': 'r1',
    'status': 'no_show',
    'changed_at': '2026-09-12T09:00:00+09:00',
    'stop_skipped': false,
    'no_show_case': {
      'case_id': caseId,
      'started_at': '2026-09-12T09:00:00+09:00',
      'expires_at': '2026-09-12T09:03:00+09:00',
    },
  };

  test('case_id 가 숫자로 와도 형변환 예외 없이 문자열로 흡수된다', () {
    final parsed = RiderUpdateResult.fromJson(response(caseId: 12));

    expect(parsed.noShowCase?.caseId, '12');
  });

  test('case_id 가 이미 문자열이면 그대로 통과한다', () {
    final parsed = RiderUpdateResult.fromJson(response(caseId: '12'));

    expect(parsed.noShowCase?.caseId, '12');
  });
}
