import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/routes/domain/route_detail.dart';

/// §3.10 (`Ruling 824`) — 노선 자세히의 "12:09 지남" 은 `stops[].arrived_at` 이 그린다.
void main() {
  Map<String, dynamic> stop(String id, {Object? arrivedAt = 'unset'}) => {
    'stop_id': id,
    'seq': 2,
    'name': '중앙공원 앞',
    'address': '경기 부천시 원미구 중앙로 61',
    'lat': 37.5,
    'lng': 126.7,
    if (arrivedAt != 'unset') 'arrived_at': arrivedAt,
  };

  test('지난 승하차지는 arrived_at 을 읽고, 아직이면 null 이다', () {
    expect(
      RouteStop.fromJson(stop('a', arrivedAt: '2026-10-03T03:09:00Z'))
          .arrivedAt,
      DateTime.utc(2026, 10, 3, 3, 9),
    );
    expect(RouteStop.fromJson(stop('b', arrivedAt: null)).arrivedAt, isNull);
    expect(RouteStop.fromJson(stop('c')).arrivedAt, isNull);
  });

  test('학원 항목의 stop_id 가 null 이면 문자열 "null" 이 아니라 null 로 읽는다', () {
    final academy = RouteStop.fromJson({...stop('x'), 'stop_id': null});

    expect(academy.stopId, isNull);
    expect(RouteStop.fromJson(stop('7')).stopId, '7');
  });
}
