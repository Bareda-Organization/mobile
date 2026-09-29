import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/map/map_surface.dart';

/// R32 M1 — 카메라를 내용에 맞출 때 쓰는 사각형. 버스가 노선 밖에 있어도 포함돼야 한다.
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

  test('마커·선의 모든 점을 감싼다', () {
    final bounds = contentBounds(
      [stopA, stopB],
      [
        const MapPolyline(
          id: 'road',
          points: [(lat: 37.4, lng: 126.9), (lat: 37.55, lng: 127.3)],
        ),
      ],
    )!;

    expect(
      [bounds.south, bounds.west, bounds.north, bounds.east],
      [37.4, 126.9, 37.6, 127.3],
    );
  });

  test('노선 밖의 버스도 사각형에 들어온다', () {
    const bus = MapMarker(
      id: 'bus',
      lat: 37.9,
      lng: 127,
      kind: MapMarkerKind.bus,
    );

    expect(contentBounds([stopA, stopB, bus], const [])!.north, 37.9);
  });

  test('점이 없으면 null, 하나면 점으로 본다', () {
    expect(contentBounds(const [], const []), isNull);
    expect(contentBounds([stopA], const [])!.isPoint, isTrue);
  });
}
