import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/map/marker_interpolator.dart';

void main() {
  const start = (lat: 37.5, lng: 127.0);
  const end = (lat: 37.6, lng: 127.2);

  group('MarkerInterpolator.at', () {
    test('진행률 0 이면 시작 좌표를 그대로 돌려준다', () {
      final result = MarkerInterpolator.at(
        start: start,
        end: end,
        progress: 0,
      );

      expect(result, start);
    });

    test('진행률 1 이면 목표 좌표를 그대로 돌려준다', () {
      final result = MarkerInterpolator.at(
        start: start,
        end: end,
        progress: 1,
      );

      expect(result, end);
    });

    test('진행률 0.5 면 두 좌표의 정확한 중간이다', () {
      final result = MarkerInterpolator.at(
        start: start,
        end: end,
        progress: 0.5,
      );

      expect(result.lat, closeTo(37.55, 1e-9));
      expect(result.lng, closeTo(127.1, 1e-9));
    });

    test('진행률이 1 을 넘어도 목표 좌표를 지나치지 않는다', () {
      // 다음 좌표가 늦게 도착해 경과 시간이 보간 시간을 넘는 상황과
      // 같다 — `COMMON-B2.md §2` "진행률이 1 을 넘지 않는다".
      final result = MarkerInterpolator.at(
        start: start,
        end: end,
        progress: 1.8,
      );

      expect(result, end);
    });

    test('진행률이 0 보다 작아도 시작 좌표 이전으로 나가지 않는다', () {
      final result = MarkerInterpolator.at(
        start: start,
        end: end,
        progress: -0.3,
      );

      expect(result, start);
    });
  });
}
