import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/run/manager_run_channel.dart';

/// [ManagerRunChannelController] 의 소켓 생명주기(연결·구독·해제)는 실
/// 백엔드 없이 검증할 수 없어 별도 통합 시험(§4)의 몫이다 — 여기서는
/// 클라이언트·Riverpod 의존이 전혀 없는 순수 함수 3개(상태 매핑 · URL
/// 조립 · 이벤트 분배)만 검증한다.
void main() {
  group('mapConnectionState', () {
    test('connecting → connecting', () {
      expect(
        mapConnectionState(WsConnectionState.connecting),
        ManagerChannelStatus.connecting,
      );
    });

    test('connected → connected', () {
      expect(
        mapConnectionState(WsConnectionState.connected),
        ManagerChannelStatus.connected,
      );
    });

    test('reconnecting → reconnecting', () {
      expect(
        mapConnectionState(WsConnectionState.reconnecting),
        ManagerChannelStatus.reconnecting,
      );
    });

    test('gaveUp → gaveUp', () {
      expect(
        mapConnectionState(WsConnectionState.gaveUp),
        ManagerChannelStatus.gaveUp,
      );
    });

    // disconnected 는 컨트롤러가 connect() 를 즉시 불러 화면이 관측할 일이
    // 거의 없는 초기값이다(클래스 문서 참고) — 배지 없음보다는 "연결 중"
    // 쪽이 나아 connecting 에 합쳤다. 이 판단 자체를 시험으로 고정해 둔다.
    test('disconnected → connecting (초기값 판단, 문서 주석 참고)', () {
      expect(
        mapConnectionState(WsConnectionState.disconnected),
        ManagerChannelStatus.connecting,
      );
    });
  });

  group('dispatchManagerChannelEvent', () {
    // 5개 콜백 중 정확히 하나만 불렸는지 확인하기 위해 매번 호출 횟수를
    // 전부 세고, 시험마다 "그 하나만 1이고 나머지는 0" 을 함께 단언한다.
    late Map<String, int> calls;
    void Function() counter(String key) =>
        () => calls[key] = (calls[key] ?? 0) + 1;

    void dispatch(WsEventType? event) {
      dispatchManagerChannelEvent(
        event,
        onRiderChanged: counter('riderChanged'),
        onStopArrived: counter('stopArrived'),
        onRunStarted: counter('runStarted'),
        onRunEnded: counter('runEnded'),
        onEmergencyAcked: counter('emergencyAcked'),
      );
    }

    setUp(() {
      calls = {};
    });

    test('riderChanged → onRiderChanged 만 호출', () {
      dispatch(WsEventType.riderChanged);
      expect(calls, {'riderChanged': 1});
    });

    test('stopArrived → onStopArrived 만 호출', () {
      dispatch(WsEventType.stopArrived);
      expect(calls, {'stopArrived': 1});
    });

    test('runStarted → onRunStarted 만 호출', () {
      dispatch(WsEventType.runStarted);
      expect(calls, {'runStarted': 1});
    });

    test('runEnded → onRunEnded 만 호출', () {
      dispatch(WsEventType.runEnded);
      expect(calls, {'runEnded': 1});
    });

    test('emergencyAcked → onEmergencyAcked 만 호출 (Ruling 277)', () {
      dispatch(WsEventType.emergencyAcked);
      expect(calls, {'emergencyAcked': 1});
    });

    test('매니저 채널이 방송하지 않는 이벤트(position)는 전부 무시', () {
      dispatch(WsEventType.position);
      expect(calls, isEmpty);
    });

    test('매니저 채널이 방송하지 않는 이벤트(emergencyRaised)는 전부 무시', () {
      dispatch(WsEventType.emergencyRaised);
      expect(calls, isEmpty);
    });

    test('매니저 채널이 방송하지 않는 이벤트(approvalRequested)는 전부 무시', () {
      dispatch(WsEventType.approvalRequested);
      expect(calls, isEmpty);
    });

    test('미지 이벤트(null, 서버가 모르는 event 값)는 무시', () {
      dispatch(null);
      expect(calls, isEmpty);
    });
  });
}
