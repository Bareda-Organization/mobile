import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/runs/domain/bus_position.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/features/live_map/domain/live_map_status.dart';
import 'package:parent_app/features/live_map/presentation/live_map_view.dart';

/// 화면이 어떤 모양을 그릴지 정하는 순수 함수 — 시안 `live-map*` 7장이 이 판정 하나로 갈린다.
/// 위젯 없이 값만 넣어 본다(판정 순서가 곧 사양이라 순서를 뒤집으면 여기서 먼저 깨진다).
void main() {
  final now = DateTime.utc(2026, 10, 4, 3, 14);

  BusPosition snapshot({
    RunStatus status = RunStatus.moving,
    double? lat = 37.5,
    DateTime? receivedAt,
    DateTime? lastSeenAt,
    DateTime? startedAt,
    DateTime? finishedAt,
    BusDelay? delay,
  }) => BusPosition(
    runId: 'r-1',
    busNo: '2호차',
    runStatus: status,
    lat: lat,
    lng: lat == null ? null : 127,
    receivedAt: lat == null ? null : (receivedAt ?? now),
    lastSeenAt: lastSeenAt,
    currentStopName: lat == null ? null : '중앙공원 앞',
    currentStopArrivedAt: lat == null ? null : DateTime.utc(2026, 10, 4, 3, 9),
    startedAt: startedAt,
    finishedAt: finishedAt,
    delay: delay,
  );

  LiveMapState connected({
    BusPosition? rest,
    AsyncValue<BusPosition>? restValue,
    WsPositionPayload? position,
    WsRunEndedPayload? runEnded,
    WsStopArrivedPayload? stopArrived,
    bool isAbsent = false,
    LiveMapConnection connection = LiveMapConnection.connected,
  }) => LiveMapState(
    connection: connection,
    restPosition: restValue ?? (rest == null ? null : AsyncValue.data(rest)),
    position: position,
    runEnded: runEnded,
    lastStopArrived: stopArrived,
    isAbsent: isAbsent,
  );

  WsPositionPayload wsPosition(DateTime at, {String? stop}) =>
      WsPositionPayload(
        lat: 37.5,
        lng: 127,
        receivedAt: at,
        currentStopName: stop,
      );

  LiveMapPhase phaseOf(LiveMapState state) =>
      LiveMapView.resolve(state, now).phase;

  group('판정 순서 — 앞의 것이 이긴다', () {
    test('결석은 연결이 끊겨 있어도 가장 먼저다', () {
      final state = connected(
        isAbsent: true,
        connection: LiveMapConnection.gaveUp,
      );
      expect(phaseOf(state), LiveMapPhase.absent);
    });

    test('연결 끊김은 "데이터 없음"(운행 전)과 겹치지 않는다 — 권한 거절은 따로 표시한다', () {
      expect(
        phaseOf(connected(connection: LiveMapConnection.gaveUp)),
        LiveMapPhase.disconnected,
      );
      final forbidden = LiveMapView.resolve(
        connected(connection: LiveMapConnection.forbidden),
        now,
      );
      expect(forbidden.phase, LiveMapPhase.disconnected);
      expect(forbidden.forbidden, isTrue);
    });

    test('연결 시도 중이거나 첫 스냅샷을 기다리는 동안은 불러오는 중이다', () {
      expect(
        phaseOf(connected(connection: LiveMapConnection.connecting)),
        LiveMapPhase.loading,
      );
      expect(
        phaseOf(connected(restValue: const AsyncValue.loading())),
        LiveMapPhase.loading,
      );
    });

    test('불러오는 중 판정은 받은 것이 있으면 하지 않는다 — 이미 아는 좌표를 스피너로 덮지 않는다', () {
      final state = connected(
        restValue: const AsyncValue.loading(),
        position: wsPosition(now),
      );
      expect(phaseOf(state), LiveMapPhase.tracking);
    });

    test('운행 종료는 방송이 멎어 좌표가 2분을 넘겼어도 "신호 없음"이 아니다', () {
      final state = connected(
        position: wsPosition(now.subtract(const Duration(minutes: 30))),
        runEnded: WsRunEndedPayload(runStatus: 'finished', finishedAt: now),
      );
      expect(phaseOf(state), LiveMapPhase.ended);
    });
  });

  group('운행 전 · 달리는 중 · 신호 없음 · 종료', () {
    test('출발 전 스냅샷(idle · confirmed)이면 운행 전 안내다', () {
      expect(
        phaseOf(connected(rest: snapshot(status: RunStatus.idle, lat: null))),
        LiveMapPhase.before,
      );
      expect(
        phaseOf(
          connected(rest: snapshot(status: RunStatus.confirmed, lat: null)),
        ),
        LiveMapPhase.before,
      );
    });

    test('스냅샷을 못 받았고(회차 없음 등) 받은 것도 없으면 운행 전 안내다', () {
      expect(
        phaseOf(
          connected(restValue: const AsyncValue.error('x', StackTrace.empty)),
        ),
        LiveMapPhase.before,
      );
    });

    test('moving 인데 좌표도 시각도 아직 없으면 운행 전이 아니라 "위치 신호 대기"다', () {
      final view = LiveMapView.resolve(
        connected(rest: snapshot(lat: null)),
        now,
      );
      expect(view.phase, LiveMapPhase.tracking);
      expect(view.position, isNull);
    });

    test('1분 59초까지는 달리는 중이고 2분이 되는 순간 신호 없음이다', () {
      final at = now.subtract(const Duration(minutes: 1, seconds: 59));
      expect(
        phaseOf(connected(position: wsPosition(at))),
        LiveMapPhase.tracking,
      );
      final lost = LiveMapView.resolve(
        connected(
          position: wsPosition(now.subtract(const Duration(minutes: 2))),
        ),
        now,
      );
      expect(lost.phase, LiveMapPhase.noSignal);
      expect(lost.staleMinutes, 2);
      expect(lost.position, isNotNull, reason: '마지막 좌표는 지도에 남긴다');
    });

    test('서버가 좌표 없이 last_seen_at 만 주면 신호 없음 · 마지막 확인 N분 전이다', () {
      final lastSeen = now.subtract(const Duration(minutes: 4));
      final view = LiveMapView.resolve(
        connected(rest: snapshot(lat: null, lastSeenAt: lastSeen)),
        now,
      );
      expect(view.phase, LiveMapPhase.noSignal);
      expect(view.staleMinutes, 4);
      expect(view.lastSeenAt, lastSeen);
      expect(view.position, isNull, reason: '좌표가 없는데 지도를 그릴 근거가 없다');
    });

    test('종료 스냅샷은 시작 · 종료 시각을 들고 종료 상태다 — 지연 띠는 없다', () {
      final started = now.subtract(const Duration(minutes: 47));
      final view = LiveMapView.resolve(
        connected(
          rest: snapshot(
            status: RunStatus.finished,
            lat: null,
            startedAt: started,
            finishedAt: now,
            delay: BusDelay(minutes: 10, sentAt: now),
          ),
        ),
        now,
      );
      expect(view.phase, LiveMapPhase.ended);
      expect(view.startedAt, started);
      expect(view.finishedAt, now);
      expect(view.delay, isNull);
    });
  });

  group('마지막으로 지난 곳', () {
    test('도착 이벤트가 있으면 이벤트의 이름 · 시각을 쓴다', () {
      final arrived = DateTime.utc(2026, 10, 4, 3, 12);
      final view = LiveMapView.resolve(
        connected(
          position: wsPosition(now, stop: '옛 이름'),
          stopArrived: WsStopArrivedPayload(
            stopId: 'st',
            seq: 1,
            name: '정문 앞',
            arrivedAt: arrived,
            nextStopId: null,
          ),
        ),
        now,
      );
      expect(view.lastStopName, '정문 앞');
      expect(view.lastStopArrivedAt, arrived);
    });

    test('이벤트가 없으면 위치가 준 이름에 스냅샷의 도착 시각을 붙인다', () {
      final view = LiveMapView.resolve(connected(rest: snapshot()), now);
      expect(view.lastStopName, '중앙공원 앞');
      expect(view.lastStopArrivedAt, DateTime.utc(2026, 10, 4, 3, 9));
    });
  });
}
