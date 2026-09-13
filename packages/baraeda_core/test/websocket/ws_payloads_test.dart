import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WsPositionPayload.fromJson', () {
    test('eta 는 부재해도 되고 원문 형태 그대로 문자열 보존된다', () {
      final payload = WsPositionPayload.fromJson({
        'lat': 37.5,
        'lng': 127.0,
        'received_at': '2026-09-13T10:00:00Z',
        'current_stop_name': '정문',
        'eta': 90,
      });

      expect(payload.lat, 37.5);
      expect(payload.lng, 127.0);
      expect(payload.currentStopName, '정문');
      expect(payload.eta, '90');
    });
  });

  group('WsStopArrivedPayload.fromJson', () {
    test('stop_id·next_stop_id 가 정수여도 문자열로 흡수한다 — Ruling 275', () {
      final payload = WsStopArrivedPayload.fromJson({
        'stop_id': 7,
        'seq': 2,
        'name': '2번 정류장',
        'arrived_at': '2026-09-13T10:00:00Z',
        'next_stop_id': 8,
      });

      expect(payload.stopId, '7');
      expect(payload.nextStopId, '8');
    });

    test('마지막 정류장은 next_stop_id 가 null 이다', () {
      final payload = WsStopArrivedPayload.fromJson({
        'stop_id': 7,
        'seq': 2,
        'name': '2번 정류장',
        'arrived_at': '2026-09-13T10:00:00Z',
        'next_stop_id': null,
      });

      expect(payload.nextStopId, isNull);
    });
  });

  group('WsRiderChangedPayload.fromJson', () {
    test('rider_id·student_id·stop_id 전부 정수에서 문자열로 흡수한다', () {
      final payload = WsRiderChangedPayload.fromJson({
        'rider_id': 1,
        'student_id': 2,
        'student_name': '홍길동',
        'status': 'boarded',
        'stop_id': 3,
        'changed_at': '2026-09-13T10:00:00Z',
        'counts': {'boarded': 1},
        'stop_skipped': false,
      });

      expect(payload.riderId, '1');
      expect(payload.studentId, '2');
      expect(payload.stopId, '3');
      expect(payload.counts, {'boarded': 1});
    });
  });

  group('WsRunStartedPayload / WsRunEndedPayload', () {
    test('run_status 고정 문자열과 카운트를 그대로 옮긴다', () {
      final started = WsRunStartedPayload.fromJson({
        'run_status': 'moving',
        'started_at': '2026-09-13T10:00:00Z',
        'auto_boarded_count': 3,
      });
      expect(started.runStatus, 'moving');
      expect(started.autoBoardedCount, 3);

      final ended = WsRunEndedPayload.fromJson({
        'run_status': 'finished',
        'finished_at': '2026-09-13T11:00:00Z',
        'auto_alighted_count': 5,
      });
      expect(ended.runStatus, 'finished');
      expect(ended.autoAlightedCount, 5);
    });
  });

  group('WsEmergencyRaisedPayload.fromJson', () {
    test('emergency_id 흡수 + 중첩 raised_by·position 파싱', () {
      final payload = WsEmergencyRaisedPayload.fromJson({
        'emergency_id': 99,
        'type': 'accident',
        'bus_no': '1호차',
        'raised_by': {'name': '기사님', 'role': 'driver', 'phone': '010'},
        'position': {'lat': 37.1, 'lng': 127.1},
        'rider_count': 4,
        'raised_at': '2026-09-13T10:00:00Z',
      });

      expect(payload.emergencyId, '99');
      expect(payload.raisedBy.name, '기사님');
      expect(payload.position.lat, 37.1);
      expect(payload.riderCount, 4);
    });
  });

  group('WsEmergencyAckedPayload.fromJson', () {
    test('emergency_id 흡수', () {
      final payload = WsEmergencyAckedPayload.fromJson({
        'emergency_id': 99,
        'acked_by_name': '원장님',
        'acked_at': '2026-09-13T10:05:00Z',
      });

      expect(payload.emergencyId, '99');
      expect(payload.ackedByName, '원장님');
    });
  });

  group('WsApprovalRequestedPayload.fromJson', () {
    test('approval_id·run_id 둘 다 흡수한다', () {
      final payload = WsApprovalRequestedPayload.fromJson({
        'approval_id': 5,
        'student_name': '홍길동',
        'run_id': 10,
        'stop_name': '정문',
        'deadline_at': '2026-09-13T09:30:00Z',
      });

      expect(payload.approvalId, '5');
      expect(payload.runId, '10');
    });
  });
}
