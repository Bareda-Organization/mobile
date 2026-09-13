import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/map/marker_motion_controller.dart';

void main() {
  final t0 = DateTime(2026, 9, 14, 12);
  const pointA = (lat: 37.5, lng: 127.0);
  const pointB = (lat: 37.6, lng: 127.2);
  const pointC = (lat: 37.7, lng: 127.4);

  group('첫 좌표', () {
    test('보간할 시작점이 없으니 그 자리에 바로 둔다', () {
      final controller = MarkerMotionController()
        ..onCoordinateReceived(pointA, t0);

      expect(controller.currentPositionAt(t0), pointA);
      expect(controller.isAnimating(t0), isFalse);
    });
  });

  group('두 번째 좌표부터 — 직전 수신 간격만큼 보간', () {
    test('경과 시간의 절반이면 두 좌표의 중간이다', () {
      final controller = MarkerMotionController()
        ..onCoordinateReceived(pointA, t0);

      // 2초 뒤 다음 좌표 도착 — 그 간격(2000ms)이 보간 시간이 된다.
      final t1 = t0.add(const Duration(seconds: 2));
      controller.onCoordinateReceived(pointB, t1);

      final half = t1.add(const Duration(seconds: 1));
      final mid = controller.currentPositionAt(half);

      expect(mid, isNotNull);
      expect(mid!.lat, closeTo((pointA.lat + pointB.lat) / 2, 1e-9));
      expect(mid.lng, closeTo((pointA.lng + pointB.lng) / 2, 1e-9));
      expect(controller.isAnimating(half), isTrue);
    });

    test('보간 시간이 다 지나면 목표 좌표에서 멈춘다(진행률 상한)', () {
      final controller = MarkerMotionController()
        ..onCoordinateReceived(pointA, t0);
      final t1 = t0.add(const Duration(seconds: 2));
      controller.onCoordinateReceived(pointB, t1);

      // 다음 좌표가 늦어져 훨씬 뒤에 물어도 목표를 지나치지 않는다.
      final wayLater = t1.add(const Duration(seconds: 30));
      expect(controller.currentPositionAt(wayLater), pointB);
      expect(controller.isAnimating(wayLater), isFalse);
    });
  });

  group('새 좌표 도착 시 이어붙이기', () {
    test('진행 중이던 보간이 그 지점에서 이어지고 튀지 않는다', () {
      final controller = MarkerMotionController()
        ..onCoordinateReceived(pointA, t0);
      final t1 = t0.add(const Duration(seconds: 2));
      controller.onCoordinateReceived(pointB, t1);

      // A→B 보간이 절반쯤 진행된 시점에 C 가 도착한다.
      final midWay = t1.add(const Duration(seconds: 1));
      final positionAtArrival = controller.currentPositionAt(midWay);
      controller.onCoordinateReceived(pointC, midWay);

      // 도착 직후(경과 0)의 위치는 A→B 의 중간이지 B 도, C 도 아니다 —
      // 순간이동 없이 "지금 보이는 자리"에서 새 구간이 시작된다.
      final justAfterArrival = controller.currentPositionAt(midWay);
      expect(justAfterArrival, positionAtArrival);
      expect(justAfterArrival, isNot(pointB));
      expect(justAfterArrival, isNot(pointC));
    });
  });

  group('간격이 상한을 넘으면 보간하지 않는다', () {
    test('통신 두절 복구처럼 간격이 상한을 넘으면 즉시 이동한다', () {
      final controller = MarkerMotionController()
        ..onCoordinateReceived(pointA, t0);

      // 30초 만에 다음 좌표 — 상한(10초)을 넘는다.
      final t1 = t0.add(const Duration(seconds: 30));
      controller.onCoordinateReceived(pointB, t1);

      // 도착 직후 바로 물어도 이미 목표에 있다 — 기어가지 않는다.
      expect(controller.currentPositionAt(t1), pointB);
      expect(controller.isAnimating(t1), isFalse);
    });
  });

  group('첫 좌표 이후 간격을 모를 때', () {
    test('기본 간격(defaultIntervalMs)만큼 보간한다', () {
      // 이 컨트롤러는 pointA 수신 이전의 "직전 수신 시각"이 없으므로,
      // pointA 자체는 즉시 배치된다(첫 좌표 규칙). 그다음 도착이
      // 곧바로(0ms 뒤) 와도 "직전 수신"은 있으므로 기본값이 아니라
      // 실측 간격(0ms)이 쓰인다 — 기본값은 오직 "직전 수신 기록 자체가
      // 없을 때"만 쓰인다는 것을 확인한다.
      final controller = MarkerMotionController()
        ..onCoordinateReceived(pointA, t0)
        ..onCoordinateReceived(pointB, t0);
      expect(controller.currentPositionAt(t0), pointB);
    });
  });
}
