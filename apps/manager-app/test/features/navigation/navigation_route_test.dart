import 'package:flutter_test/flutter_test.dart';
import 'package:kakao_flutter_sdk_navi/kakao_flutter_sdk_navi.dart';
import 'package:manager_app/features/navigation/data/kakao_navi_launcher.dart';
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

  group('kakaoNaviRequest — 공식 SDK 에 넘기는 요청', () {
    final route = NavigationRoute.fromJson(_json);

    test('목적지와 경유지를 x=경도 · y=위도 문자열로, 순서 그대로 싣는다', () {
      final request = kakaoNaviRequest(route);

      expect(request.destination.toJson(), {
        'name': '바른학원',
        'x': '127.03',
        'y': '37.53',
      });
      expect(request.viaList.map((p) => p.name), [
        '한빛아파트 정문',
        '중앙로 스타빌딩 앞',
      ]);
      expect(request.viaList.first.x, '127.01');
      expect(request.viaList.first.y, '37.51');
    });

    test('좌표계를 wgs84 로 못 박고 차종은 지정하지 않는다', () {
      final option = kakaoNaviRequest(route).option;

      // SDK 서버 기본값은 KATEC 이라 빠지면 좌표가 엉뚱한 곳을 가리킨다.
      expect(option.coordType, CoordType.wgs84);
      // 기사가 카카오내비 앱에 설정해 둔 차종을 따른다.
      expect(option.vehicleType, isNull);
    });

    test('경유지가 없으면 viaList 가 비어 있다', () {
      final direct = NavigationRoute.fromJson({
        ..._json,
        'waypoints': <dynamic>[],
      });

      expect(kakaoNaviRequest(direct).viaList, isEmpty);
    });
  });
}
