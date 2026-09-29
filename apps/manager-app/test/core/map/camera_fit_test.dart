import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/map/map_surface.dart';

/// R33 M2 — 카메라 맞춤은 **노선**(승하차지 핀 + 도로 경로) 기준이다. 버스는 노선 사각형을 약 2km
/// 넓힌 범위 안일 때만 맞춤에 넣는다. 오래된 위치로 버스가 노선에서 아주 멀면 세계 지도까지 넓어지던
/// 결함(시뮬레이터 실측)을 막는다.
void main() {
  const stopA = MapMarker(
    id: 'a',
    lat: 37.5,
    lng: 127,
    kind: MapMarkerKind.stop,
  );
  const stopB = MapMarker(
    id: 'b',
    lat: 37.6,
    lng: 127.2,
    kind: MapMarkerKind.stop,
  );
  const road = MapPolyline(
    id: 'road',
    points: [(lat: 37.45, lng: 126.95), (lat: 37.62, lng: 127.25)],
  );

  /// 노선 사각형(남 37.45 · 서 126.95 · 북 37.62 · 동 127.25) 바깥으로 [meters] 만큼 나간 버스.
  MapMarker busNorthOf({required double meters}) => MapMarker(
    id: 'bus',
    lat: 37.62 + meters / 111320,
    lng: 127.1,
    kind: MapMarkerKind.bus,
  );

  MapMarker busEastOf({required double meters}) => MapMarker(
    id: 'bus',
    lat: 37.5,
    // 경도 1도의 길이는 위도에 따라 줄어든다 — 그 위도에서 재야 "2km" 가 맞다.
    lng: 127.25 + meters / (111320 * math.cos(37.5 * math.pi / 180)),
    kind: MapMarkerKind.bus,
  );

  test('멀리 있는 버스는 사각형에서 빠지고 노선만 감싼다', () {
    const farBus = MapMarker(
      id: 'bus',
      lat: 0,
      lng: 0,
      kind: MapMarkerKind.bus,
    );

    final fit = cameraFit([stopA, stopB, farBus], [road])!;

    expect(
      [
        fit.bounds.south,
        fit.bounds.west,
        fit.bounds.north,
        fit.bounds.east,
      ],
      [37.45, 126.95, 37.62, 127.25],
    );
    expect(fit.markerIds, {'a', 'b'});
  });

  test('노선 안에 있는 버스는 사각형에 넣는다', () {
    const insideBus = MapMarker(
      id: 'bus',
      lat: 37.55,
      lng: 127.1,
      kind: MapMarkerKind.bus,
    );

    final fit = cameraFit([stopA, stopB, insideBus], [road])!;

    expect(fit.markerIds, {'a', 'b', 'bus'});
    expect(fit.bounds.north, 37.62);
  });

  test('경계 — 노선 사각형에서 2km 안쪽이면 포함하고 사각형도 그만큼 넓어진다', () {
    final fit = cameraFit([stopA, stopB, busNorthOf(meters: 1900)], [road])!;

    expect(fit.markerIds, contains('bus'));
    expect(fit.bounds.north, closeTo(37.62 + 1900 / 111320, 1e-9));
  });

  test('경계 — 2km 를 넘으면 빠진다', () {
    final fit = cameraFit([stopA, stopB, busNorthOf(meters: 2100)], [road])!;

    expect(fit.markerIds, {'a', 'b'});
    expect(fit.bounds.north, 37.62);
  });

  test('경도 방향도 그 위도의 실제 거리로 잰다', () {
    expect(
      cameraFit([stopA, stopB, busEastOf(meters: 1900)], [road])!.markerIds,
      contains('bus'),
    );
    expect(
      cameraFit([stopA, stopB, busEastOf(meters: 2100)], [road])!.markerIds,
      isNot(contains('bus')),
    );
  });

  test('버스가 가까워지면 포함 여부가 바뀌어 맞춤 대상 id 가 달라진다', () {
    final far = cameraFit([stopA, stopB, busNorthOf(meters: 50000)], [road])!;
    final near = cameraFit([stopA, stopB, busNorthOf(meters: 500)], [road])!;

    expect(far.markerIds, isNot(equals(near.markerIds)));
    expect(far.signature, isNot(near.signature));
    // 버스 좌표만 바뀌고 포함 여부가 같으면 다시 맞추지 않는다.
    final nearer = cameraFit([stopA, stopB, busNorthOf(meters: 300)], [road])!;
    expect(near.signature, nearer.signature);
  });

  test('노선이 없으면 버스만이라도 맞춘다', () {
    const bus = MapMarker(
      id: 'bus',
      lat: 37.5,
      lng: 127,
      kind: MapMarkerKind.bus,
    );

    final fit = cameraFit([bus], const [])!;

    expect(fit.markerIds, {'bus'});
    expect(fit.bounds.isPoint, isTrue);
  });

  test('아무것도 없으면 null', () {
    expect(cameraFit(const [], const []), isNull);
  });
}
