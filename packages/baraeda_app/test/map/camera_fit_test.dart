import 'dart:math' as math;

import 'package:baraeda_app/map/map_fit.dart';
import 'package:baraeda_app/map/map_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// R33 M2 — 카메라 맞춤은 **노선**(승하차지 핀 + 도로 경로) 기준이다. 버스는 노선 사각형을 약 2km
/// 넓힌 범위 안일 때만 맞춤에 넣는다. 오래된 위치로 버스가 노선에서 아주 멀면 세계 지도까지 넓어지던
/// 결함(시뮬레이터 실측)을 막는다.
/// 매니저 앱 설정 — 노선 사각형을 2km 넓힌 범위 안의 버스만 맞춤에 넣는다.
MapFit? withBus(Iterable<MapMarker> markers, Iterable<MapPolyline> polylines) =>
    cameraFit(markers, polylines, busMarginMeters: busFitMarginMeters);

/// 학부모 앱 설정 — 버스는 맞춤에서 뺀다.
MapFit? withoutBus(
  Iterable<MapMarker> markers,
  Iterable<MapPolyline> polylines,
) => cameraFit(markers, polylines, busMarginMeters: null);

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

    final fit = withBus([stopA, stopB, farBus], [road])!;

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

    final fit = withBus([stopA, stopB, insideBus], [road])!;

    expect(fit.markerIds, {'a', 'b', 'bus'});
    expect(fit.bounds.north, 37.62);
  });

  test('경계 — 노선 사각형에서 2km 안쪽이면 포함하고 사각형도 그만큼 넓어진다', () {
    final fit = withBus([stopA, stopB, busNorthOf(meters: 1900)], [road])!;

    expect(fit.markerIds, contains('bus'));
    expect(fit.bounds.north, closeTo(37.62 + 1900 / 111320, 1e-9));
  });

  test('경계 — 2km 를 넘으면 빠진다', () {
    final fit = withBus([stopA, stopB, busNorthOf(meters: 2100)], [road])!;

    expect(fit.markerIds, {'a', 'b'});
    expect(fit.bounds.north, 37.62);
  });

  test('경도 방향도 그 위도의 실제 거리로 잰다', () {
    expect(
      withBus([stopA, stopB, busEastOf(meters: 1900)], [road])!.markerIds,
      contains('bus'),
    );
    expect(
      withBus([stopA, stopB, busEastOf(meters: 2100)], [road])!.markerIds,
      isNot(contains('bus')),
    );
  });

  test('버스가 가까워지면 포함 여부가 바뀌어 맞춤 대상 id 가 달라진다', () {
    final far = withBus([stopA, stopB, busNorthOf(meters: 50000)], [road])!;
    final near = withBus([stopA, stopB, busNorthOf(meters: 500)], [road])!;

    expect(far.markerIds, isNot(equals(near.markerIds)));
    expect(far.signature, isNot(near.signature));
    // 버스 좌표만 바뀌고 포함 여부가 같으면 다시 맞추지 않는다.
    final nearer = withBus([stopA, stopB, busNorthOf(meters: 300)], [road])!;
    expect(near.signature, nearer.signature);
  });

  test('노선이 없으면 버스만이라도 맞춘다', () {
    const bus = MapMarker(
      id: 'bus',
      lat: 37.5,
      lng: 127,
      kind: MapMarkerKind.bus,
    );

    final fit = withBus([bus], const [])!;

    expect(fit.markerIds, {'bus'});
    expect(fit.bounds.isPoint, isTrue);
  });

  test('아무것도 없으면 null', () {
    expect(withBus(const [], const []), isNull);
  });

  test('같은 마커라도 선이 달라지면 맞춤 서명이 달라져 다시 맞춘다', () {
    // 도로 경로는 지도가 뜬 뒤에 도착하기도 한다 — 마커 id 만 비교하면 선이 생겨도 옛 화면이 남는다.
    const otherRoad = MapPolyline(
      id: 'road',
      points: [(lat: 37.4, lng: 126.9), (lat: 37.7, lng: 127.3)],
    );

    final withRoad = withBus([stopA, stopB], [road])!;
    final withOtherRoad = withBus([stopA, stopB], [otherRoad])!;
    final withoutRoad = withBus([stopA, stopB], const [])!;

    expect(withRoad.signature, isNot(withOtherRoad.signature));
    expect(withRoad.signature, isNot(withoutRoad.signature));
    expect(withRoad.signature, withBus([stopA, stopB], [road])!.signature);
  });

  group('버스를 맞춤에서 빼는 설정(busMarginMeters: null)', () {
    test('노선 안에 있는 버스도 사각형 · 마커 id 에서 뺀다', () {
      const insideBus = MapMarker(
        id: 'bus',
        lat: 37.55,
        lng: 127.1,
        kind: MapMarkerKind.bus,
      );

      final fit = withoutBus([stopA, stopB, insideBus], [road])!;

      expect(fit.markerIds, {'a', 'b'});
      expect(
        [
          fit.bounds.south,
          fit.bounds.west,
          fit.bounds.north,
          fit.bounds.east,
        ],
        [37.45, 126.95, 37.62, 127.25],
      );
    });

    test('버스 좌표가 바뀌어도 서명이 같아 다시 맞추지 않는다', () {
      final a = withoutBus([stopA, stopB, busNorthOf(meters: 500)], [road])!;
      final b = withoutBus([stopA, stopB, busNorthOf(meters: 50000)], [road])!;

      expect(a.signature, b.signature);
    });

    test('노선이 없으면 버스만 있어도 맞출 대상이 없다', () {
      const bus = MapMarker(
        id: 'bus',
        lat: 37.5,
        lng: 127,
        kind: MapMarkerKind.bus,
      );

      expect(withoutBus([bus], const []), isNull);
    });

    test('버스가 아닌 마커 하나뿐이면 점 사각형이다', () {
      final fit = withoutBus([stopA], const [])!;

      expect(fit.bounds.isPoint, isTrue);
      expect(fit.markerIds, {'a'});
    });
  });
}
