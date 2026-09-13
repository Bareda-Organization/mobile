import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebSocketEnvelope.fromJson', () {
    test('run_id 가 원문 정수(Long)여도 문자열로 흡수한다 — Ruling 275', () {
      final envelope = WebSocketEnvelope.fromJson({
        'event': 'position',
        'run_id': 42,
        'occurred_at': '2026-09-13T10:00:00Z',
        'payload': <String, dynamic>{},
      });

      expect(envelope.runId, '42');
      expect(envelope.runId, isA<String>());
    });

    test('알려진 이벤트 문자열은 WsEventType 으로 매핑된다', () {
      final envelope = WebSocketEnvelope.fromJson({
        'event': 'run_started',
        'run_id': 1,
        'occurred_at': '2026-09-13T10:00:00Z',
        'payload': <String, dynamic>{},
      });

      expect(envelope.event, WsEventType.runStarted);
      expect(envelope.eventWireValue, 'run_started');
    });

    test('모르는 이벤트 문자열은 죽지 않고 event 가 null 이 된다', () {
      final envelope = WebSocketEnvelope.fromJson({
        'event': 'bus_relocated',
        'run_id': 1,
        'occurred_at': '2026-09-13T10:00:00Z',
        'payload': <String, dynamic>{},
      });

      expect(envelope.event, isNull);
      expect(envelope.eventWireValue, 'bus_relocated');
    });

    test('payload 는 재파싱을 위해 원문 Map 그대로 보존한다', () {
      final envelope = WebSocketEnvelope.fromJson({
        'event': 'position',
        'run_id': 1,
        'occurred_at': '2026-09-13T10:00:00Z',
        'payload': {'lat': 37.5, 'lng': 127.0},
      });

      expect(envelope.payload, {'lat': 37.5, 'lng': 127.0});
    });
  });
}
