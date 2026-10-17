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

    // Ruling 335 — 학생 채널(`/topic/students/{id}/run`)은 인원수를 싣지 않는다(C-08).
    // 필수로 읽으면 학부모 앱이 운행 시작·종료 이벤트를 받는 순간 예외가 난다.
    test('학생 채널처럼 인원수가 없으면 null 로 둔다', () {
      final started = WsRunStartedPayload.fromJson({
        'run_status': 'moving',
        'started_at': '2026-09-13T10:00:00Z',
      });
      expect(started.autoBoardedCount, isNull);

      final ended = WsRunEndedPayload.fromJson({
        'run_status': 'finished',
        'finished_at': '2026-09-13T11:00:00Z',
      });
      expect(ended.autoAlightedCount, isNull);
    });
  });
}
