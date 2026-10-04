import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/features/live_map/domain/bus_position.dart';

/// §3.11 (`Ruling 821`) — 홈 지도 미리보기와 지도 화면이 REST 스냅샷만으로 시각 · 지연 띠를 그린다.
void main() {
  Map<String, dynamic> body({Map<String, dynamic>? extra}) => {
    'run_id': 'run-1',
    'bus_no': '2호차',
    'run_status': 'moving',
    'lat': 37.5,
    'lng': 126.7,
    'received_at': '2026-10-03T03:14:00Z',
    'current_stop_name': '중앙공원 앞',
    ...?extra,
  };

  test('운행 시작 · 종료 시각과 마지막으로 지난 곳의 도착 시각을 읽는다', () {
    final position = BusPosition.fromJson(
      body(
        extra: {
          'started_at': '2026-10-03T03:05:00Z',
          'finished_at': '2026-10-03T03:52:00Z',
          'current_stop_arrived_at': '2026-10-03T03:09:00Z',
        },
      ),
    );

    expect(position.startedAt, DateTime.utc(2026, 10, 3, 3, 5));
    expect(position.finishedAt, DateTime.utc(2026, 10, 3, 3, 52));
    expect(position.currentStopArrivedAt, DateTime.utc(2026, 10, 3, 3, 9));
  });

  test('지연 안내(delay)는 minutes · reason · sent_at 을 읽는다', () {
    final position = BusPosition.fromJson(
      body(
        extra: {
          'delay': {
            'minutes': 10,
            'reason': '교통 체증',
            'sent_at': '2026-10-03T03:12:00Z',
          },
        },
      ),
    );

    expect(position.delay?.minutes, 10);
    expect(position.delay?.reason, '교통 체증');
    expect(position.delay?.sentAt, DateTime.utc(2026, 10, 3, 3, 12));
  });

  test('새 필드가 없거나 null 이어도 깨지지 않고 모두 null 이다(백엔드가 아직 안 줄 때)', () {
    final missing = BusPosition.fromJson(body());
    final explicitNull = BusPosition.fromJson(
      body(extra: {'delay': null, 'started_at': null, 'finished_at': null}),
    );

    for (final position in [missing, explicitNull]) {
      expect(position.delay, isNull);
      expect(position.startedAt, isNull);
      expect(position.finishedAt, isNull);
      expect(position.currentStopArrivedAt, isNull);
    }
  });

  test('사유 없는 지연도 읽는다(reason 은 선택)', () {
    final position = BusPosition.fromJson(
      body(
        extra: {
          'delay': {'minutes': 5, 'sent_at': '2026-10-03T03:12:00Z'},
        },
      ),
    );

    expect(position.delay?.minutes, 5);
    expect(position.delay?.reason, isNull);
  });
}
