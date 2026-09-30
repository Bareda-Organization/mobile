import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WsEventType.fromWireValueOrNull', () {
    test('10개 이벤트 전부 원문 값으로 매칭된다', () {
      expect(WsEventType.fromWireValueOrNull('position'), WsEventType.position);
      expect(
        WsEventType.fromWireValueOrNull('stop_arrived'),
        WsEventType.stopArrived,
      );
      expect(
        WsEventType.fromWireValueOrNull('rider_changed'),
        WsEventType.riderChanged,
      );
      expect(
        WsEventType.fromWireValueOrNull('run_started'),
        WsEventType.runStarted,
      );
      expect(
        WsEventType.fromWireValueOrNull('run_ended'),
        WsEventType.runEnded,
      );
      expect(
        WsEventType.fromWireValueOrNull('emergency_raised'),
        WsEventType.emergencyRaised,
      );
      expect(
        WsEventType.fromWireValueOrNull('emergency_acked'),
        WsEventType.emergencyAcked,
      );
      expect(
        WsEventType.fromWireValueOrNull('emergency_canceled'),
        WsEventType.emergencyCanceled,
      );
      expect(
        WsEventType.fromWireValueOrNull('approval_requested'),
        WsEventType.approvalRequested,
      );
      expect(
        WsEventType.fromWireValueOrNull('route_changed'),
        WsEventType.routeChanged,
      );
    });

    test('모르는 값·null 은 null — 서버가 이벤트를 추가해도 죽지 않는다', () {
      expect(WsEventType.fromWireValueOrNull('bus_relocated'), isNull);
      expect(WsEventType.fromWireValueOrNull(null), isNull);
    });
  });
}
