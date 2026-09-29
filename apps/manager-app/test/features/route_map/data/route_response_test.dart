import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';

/// R32 M1 — 서버가 `road_path`·`fallback_used` 를 얹기 전 응답과 얹은 응답을 둘 다 읽는다.
void main() {
  const stop = {
    'stop_id': 's1',
    'seq': 1,
    'name': '1번',
    'lat': 37.5,
    'lng': 127.0,
  };

  test('두 필드가 없는 옛 응답은 빈 선 · 근사 아님으로 읽는다', () {
    final route = RouteResponse.fromJson({
      'stops': [stop],
    });

    expect(route.roadPath, isEmpty);
    expect(route.fallbackUsed, isFalse);
  });

  test('road_path 와 fallback_used 가 있으면 그대로 읽는다', () {
    final route = RouteResponse.fromJson({
      'stops': [stop],
      'road_path': [
        {'lat': 37.5, 'lng': 127.0},
        {'lat': 37, 'lng': 127.1},
      ],
      'fallback_used': true,
    });

    expect(route.roadPath, [(lat: 37.5, lng: 127.0), (lat: 37.0, lng: 127.1)]);
    expect(route.fallbackUsed, isTrue);
  });
}
