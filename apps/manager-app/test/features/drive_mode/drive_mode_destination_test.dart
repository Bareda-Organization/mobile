import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';

/// BR-002 · Ruling 327 — 서버가 §4.2 명단 맨 뒤에 학원 항목(`is_destination`,
/// 학생 없음)을 싣기 시작해도 앱은 코드 수정 없이 그 항목을 "다음 도착 처리"
/// 대상으로 고른다. 이게 깨지면 등원 운행을 끝낼 버튼이 사라진다.
void main() {
  test('마지막 승차지 도착 뒤 다음 도착 처리 대상은 학원 항목이다', () {
    final roster = RosterResponse.fromJson({
      'run_id': '31',
      'bus_no': '3호차',
      'direction': 'to_academy',
      'counts': {'boarded': 1, 'waiting': 0, 'no_show': 0, 'absent_n': 0},
      'stops': [
        {
          'stop_id': '901',
          'seq': 1,
          'name': '중앙로 스타빌딩 앞',
          'address': '서울 중구',
          'arrived_at': '2026-09-25T08:41:12+09:00',
          'is_destination': false,
          'students': <Map<String, dynamic>>[],
        },
        {
          'stop_id': '902',
          'seq': 2,
          'name': '바래다학원 A',
          'address': null,
          'is_destination': true,
          'students': <Map<String, dynamic>>[],
        },
      ],
    });

    final next = nextUnarrivedStop(roster);

    expect(next?.stopId, '902');
    expect(next?.name, '바래다학원 A');
  });

  // M1(Ruling 341, BR-016) — DriveMode 는 `driveModeRosterProvider` 로 같은
  // §4.2 응답·모델을 소비한다. `absent`(`change=removed`) 학생이 섞여 있어도
  // 파싱이 깨지지 않고, 정류장 자체의 도착 판정(`nextUnarrivedStop`)은
  // 학생 개인 상태와 무관하게 그대로 동작해야 한다.
  test('absent·removed 학생이 섞여도 명단 파싱과 다음 도착지 계산이 그대로다', () {
    final roster = RosterResponse.fromJson({
      'run_id': '31',
      'bus_no': '3호차',
      'direction': 'to_academy',
      'counts': {'boarded': 1, 'waiting': 0, 'no_show': 0, 'absent_n': 1},
      'stops': [
        {
          'stop_id': '901',
          'seq': 1,
          'name': '중앙로 스타빌딩 앞',
          'address': '서울 중구',
          'arrived_at': '2026-09-25T08:41:12+09:00',
          'students': [
            {
              'rider_id': 'r1',
              'student_id': 's1',
              'name': '김바래',
              'photo_url': null,
              'guardian_phone': null,
              'can_go_alone': false,
              'status': 'absent',
              'change': 'removed',
            },
          ],
        },
        {
          'stop_id': '902',
          'seq': 2,
          'name': '바래다학원 A',
          'address': null,
          'students': <Map<String, dynamic>>[],
        },
      ],
    });

    final absentStudent = roster.stops.first.students.single;
    expect(absentStudent.status, RiderStatus.absent);
    expect(absentStudent.change, RiderChange.removed);

    final next = nextUnarrivedStop(roster);
    expect(next?.stopId, '902');
  });
}
