import 'package:flutter_test/flutter_test.dart';
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
}
