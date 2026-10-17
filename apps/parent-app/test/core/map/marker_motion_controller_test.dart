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
        ..onCoordinateReceived('bus', pointA, t0);

      expect(controller.positionAt('bus', t0), pointA);
      expect(controller.isAnimating(t0), isFalse);
    });

    test('좌표를 받은 적 없는 마커는 위치가 없다', () {
      expect(MarkerMotionController().positionAt('none', t0), isNull);
    });
  });

  group('두 번째 좌표부터 — 직전 수신 간격만큼 보간', () {
    test('경과 시간의 절반이면 두 좌표의 중간이다', () {
      final controller = MarkerMotionController()
        ..onCoordinateReceived('bus', pointA, t0);

      // 2초 뒤 다음 좌표 도착 — 그 간격(2000ms)이 보간 시간이 된다.
      final t1 = t0.add(const Duration(seconds: 2));
      controller.onCoordinateReceived('bus', pointB, t1);

      final half = t1.add(const Duration(seconds: 1));
      final mid = controller.positionAt('bus', half);

      expect(mid, isNotNull);
      expect(mid!.lat, closeTo((pointA.lat + pointB.lat) / 2, 1e-9));
      expect(mid.lng, closeTo((pointA.lng + pointB.lng) / 2, 1e-9));
      expect(controller.isAnimating(half), isTrue);
    });

    test('보간 시작 순간은 시작 좌표, 끝나는 순간은 목표 좌표다', () {
      final controller = MarkerMotionController()
        ..onCoordinateReceived('bus', pointA, t0);
      final t1 = t0.add(const Duration(seconds: 2));
      controller.onCoordinateReceived('bus', pointB, t1);

      expect(controller.positionAt('bus', t1), pointA);
      expect(
        controller.positionAt('bus', t1.add(const Duration(seconds: 2))),
        pointB,
      );
    });

    test('보간 시간이 다 지나면 목표 좌표에서 멈춘다(진행률 상한)', () {
      final controller = MarkerMotionController()
        ..onCoordinateReceived('bus', pointA, t0);
      final t1 = t0.add(const Duration(seconds: 2));
      controller.onCoordinateReceived('bus', pointB, t1);

      // 다음 좌표가 늦어져 훨씬 뒤에 물어도 목표를 지나치지 않는다.
      final wayLater = t1.add(const Duration(seconds: 30));
      expect(controller.positionAt('bus', wayLater), pointB);
      expect(controller.isAnimating(wayLater), isFalse);
    });

    test('시작 시각보다 이른 시각을 물어도 시작 좌표 이전으로 나가지 않는다', () {
      final controller = MarkerMotionController()
        ..onCoordinateReceived('bus', pointA, t0);
      final t1 = t0.add(const Duration(seconds: 2));
      controller.onCoordinateReceived('bus', pointB, t1);

      expect(
        controller.positionAt('bus', t1.subtract(const Duration(seconds: 1))),
        pointA,
      );
    });
  });

  group('새 좌표 도착 시 이어붙이기', () {
    test('진행 중이던 보간이 그 지점에서 이어지고 튀지 않는다', () {
      final controller = MarkerMotionController()
        ..onCoordinateReceived('bus', pointA, t0);
      final t1 = t0.add(const Duration(seconds: 2));
      controller.onCoordinateReceived('bus', pointB, t1);

      // A→B 보간이 절반쯤 진행된 시점에 C 가 도착한다.
      final midWay = t1.add(const Duration(seconds: 1));
      final positionAtArrival = controller.positionAt('bus', midWay);
      controller.onCoordinateReceived('bus', pointC, midWay);

      // 도착 직후(경과 0)의 위치는 A→B 의 중간이지 B 도, C 도 아니다 —
      // 순간이동 없이 "지금 보이는 자리"에서 새 구간이 시작된다.
      final justAfterArrival = controller.positionAt('bus', midWay);
      expect(justAfterArrival, positionAtArrival);
      expect(justAfterArrival, isNot(pointB));
      expect(justAfterArrival, isNot(pointC));
    });
  });

  group('간격이 상한을 넘으면 보간하지 않는다', () {
    test('통신 두절 복구처럼 간격이 상한을 넘으면 즉시 이동한다', () {
      final controller = MarkerMotionController()
        ..onCoordinateReceived('bus', pointA, t0);

      // 30초 만에 다음 좌표 — 상한(10초)을 넘는다.
      final t1 = t0.add(const Duration(seconds: 30));
      controller.onCoordinateReceived('bus', pointB, t1);

      // 도착 직후 바로 물어도 이미 목표에 있다 — 기어가지 않는다.
      expect(controller.positionAt('bus', t1), pointB);
      expect(controller.isAnimating(t1), isFalse);
    });
  });

  group('첫 좌표 이후 간격을 모를 때', () {
    test('직전 수신 시각이 있으면 기본값이 아니라 실측 간격(0ms)이 쓰인다', () {
      // 기본 간격은 "직전 수신 기록 자체가 없을 때"만 쓰인다 — 두 번째 좌표가 곧바로(0ms 뒤) 와도
      // 직전 수신은 있으므로 보간 없이 목표에 있다.
      final controller = MarkerMotionController()
        ..onCoordinateReceived('bus', pointA, t0)
        ..onCoordinateReceived('bus', pointB, t0);
      expect(controller.positionAt('bus', t0), pointB);
    });
  });

  test('같은 좌표를 다시 받으면 보간 중이 아니다', () {
    final controller = MarkerMotionController()
      ..onCoordinateReceived('stop', pointA, t0)
      ..onCoordinateReceived(
        'stop',
        pointA,
        t0.add(const Duration(seconds: 1)),
      );

    expect(
      controller.isAnimating(
        t0.add(const Duration(seconds: 1, milliseconds: 100)),
      ),
      isFalse,
    );
  });

  group('프레임마다 옮길 마커 고르기', () {
    final end = t0.add(const Duration(seconds: 4));

    MarkerMotionController fixture() => MarkerMotionController()
      ..onCoordinateReceived('bus', pointA, t0)
      ..onCoordinateReceived('bus', pointB, t0.add(const Duration(seconds: 2)))
      ..onCoordinateReceived('stop-1', pointC, t0)
      ..onCoordinateReceived('stop-2', pointC, t0);

    test('보간 중인 버스만 고르고 정차지는 고르지 않는다', () {
      final ids = fixture().idsToMove(t0.add(const Duration(seconds: 3)));

      expect(ids, ['bus']);
    });

    test('보간이 끝난 첫 프레임에는 마지막 자리에 놓기 위해 한 번 더 고르고 그다음은 고르지 않는다', () {
      final controller = fixture()
        ..idsToMove(t0.add(const Duration(seconds: 3)));

      expect(controller.idsToMove(end), ['bus']);
      expect(
        controller.idsToMove(end.add(const Duration(seconds: 1))),
        isEmpty,
      );
    });

    test('지도에서 사라진 마커는 더 고르지 않는다', () {
      final controller = fixture()..remove('bus');

      expect(controller.idsToMove(t0.add(const Duration(seconds: 3))), isEmpty);
      expect(controller.positionAt('bus', end), isNull);
    });
  });
}
