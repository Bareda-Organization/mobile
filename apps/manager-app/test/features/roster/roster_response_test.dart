import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';

/// §4.2 `students[]` 파싱 — BR-082. 보호자가 아직 연결되지 않은 학생(관계자가 먼저 등록, P-02 로
/// 나중에 연결)은 서버가 `guardian_phone: null` 을 내린다(§1.13 목록, `○`). 한 명의 부재가 명단
/// 전체 파싱을 죽이면 안 된다.
void main() {
  Map<String, dynamic> student({Object? guardianPhone}) => {
        'rider_id': '1',
        'student_id': '2',
        'name': '학생',
        'photo_url': null,
        'guardian_phone': guardianPhone,
        'can_go_alone': false,
        'status': 'waiting',
      };

  test('보호자 미연결 학생(guardian_phone null)도 파싱되고 값은 null 이다', () {
    final parsed = RosterStudent.fromJson(student());

    expect(parsed.guardianPhone, isNull);
  });

  test('보호자 연락처가 있으면 마스킹된 값 그대로다', () {
    final parsed =
        RosterStudent.fromJson(student(guardianPhone: '010-2XXX-8814'));

    expect(parsed.guardianPhone, '010-2XXX-8814');
  });
}
