import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/navigation/data/models/navigation_route.dart';

/// API_SPEC §4.16 응답 — 경유지 2개 + 목적지, 상한 때문에 잘린 경우.
const _json = <String, dynamic>{
  'provider': 'kakao',
  'waypoints': [
    {
      'lat': 37.51,
      'lng': 127.01,
      'name': '한빛아파트 정문',
      'stop_id': 's1',
      'seq': 2,
    },
    {
      'lat': 37.52,
      'lng': 127.02,
      'name': '중앙로 스타빌딩 앞',
      'stop_id': 's2',
      'seq': 4,
    },
  ],
  'destination': {'lat': 37.53, 'lng': 127.03, 'name': '바른학원', 'stop_id': 's9'},
  'truncated': true,
  'truncated_reason': '남은 승하차지가 많아 앞 4곳만 넘겼습니다',
  'total_remaining_stops': 7,
};

void main() {
  group('NavigationRoute.fromJson (§4.16)', () {
    test('경유지·목적지·잘림 여부를 읽는다', () {
      final route = NavigationRoute.fromJson(_json);

      expect(route.provider, 'kakao');
      expect(route.waypoints.map((p) => p.name), ['한빛아파트 정문', '중앙로 스타빌딩 앞']);
      expect(route.destination.name, '바른학원');
      expect(route.truncated, isTrue);
      expect(route.truncatedReason, contains('앞 4곳'));
      expect(route.totalRemainingStops, 7);
    });

    test('출발지(origin)가 없어도 읽힌다 — 운행 중이면 서버가 싣지 않는다', () {
      expect(NavigationRoute.fromJson(_json).origin, isNull);
    });
  });

  group('kakaoNaviUri — 카카오내비로 넘기는 주소', () {
    final route = NavigationRoute.fromJson(_json);

    Map<String, dynamic> paramOf(Uri uri) =>
        jsonDecode(uri.queryParameters['param']!) as Map<String, dynamic>;

    test('목적지와 경유지를 x=경도 · y=위도로, 순서 그대로 싣고 앱 키를 붙인다', () {
      final uri = kakaoNaviUri(route, appKey: 'KEY-1');

      expect(uri.scheme, 'kakaonavi-sdk');
      expect(uri.host, 'navigate');
      expect(uri.queryParameters['appkey'], 'KEY-1');
      final param = paramOf(uri);
      expect(param['destination'], {
        'name': '바른학원',
        'x': 127.03,
        'y': 37.53,
      });
      final via = (param['via_list'] as List).cast<Map<String, dynamic>>();
      expect(via.map((p) => p['name']), ['한빛아파트 정문', '중앙로 스타빌딩 앞']);
      expect(via.first['x'], 127.01);
      expect(via.first['y'], 37.51);
      expect((param['option'] as Map)['coord_type'], 'wgs84');
    });

    test('경유지가 없으면 via_list 를 싣지 않는다', () {
      final direct = NavigationRoute.fromJson({
        ..._json,
        'waypoints': <dynamic>[],
      });

      expect(
        paramOf(kakaoNaviUri(direct, appKey: 'k')).containsKey('via_list'),
        isFalse,
      );
    });
  });
}
