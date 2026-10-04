import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/map/map_surface.dart';
import 'package:parent_app/core/routes/domain/route_detail.dart';
import 'package:parent_app/core/routes/presentation/route_map_overlay.dart';

/// R49 `Ruling 831` — 지도에는 §3.10 이 준 표시 범위 승하차지의 번호(실제 `seq`)와 그 사이 경로선만 그린다.
/// 도로 좌표(`road_path`)가 2점 미만이면 표시 승하차지를 점선으로 잇는다.
void main() {
  RouteStop stop(
    int seq, {
    DateTime? arrivedAt,
    double? lat,
    double? lng,
    String? id,
  }) => RouteStop(
    stopId: id ?? 's$seq',
    seq: seq,
    name: '정류장$seq',
    address: null,
    lat: lat ?? 37.5 + seq / 1000,
    lng: lng ?? 126.7 + seq / 1000,
    arrivedAt: arrivedAt,
  );

  RouteDetail route({
    required List<RouteStop> stops,
    String myStopId = 's4',
    List<({double lat, double lng})> roadPath = const [],
  }) => RouteDetail(
    runId: 'r-1',
    busNo: '2호차',
    departTime: DateTime.utc(2026, 10, 5, 3, 20),
    confirmed: true,
    driver: const RouteDriver(name: null),
    escort: const RouteEscort(name: null, phone: null),
    myStopId: myStopId,
    stops: stops,
    roadPath: roadPath,
  );

  final road = [
    (lat: 37.501, lng: 126.701),
    (lat: 37.5015, lng: 126.7025),
    (lat: 37.503, lng: 126.703),
    (lat: 37.504, lng: 126.704),
  ];

  RouteMapOverlay overlay(
    RouteDetail r, {
    bool ended = false,
    bool markNext = false,
  }) => RouteMapOverlay.of(r, idPrefix: 'p', ended: ended, markNext: markNext);

  test('road_path 가 있으면 도로 경로선 1개와, 표시 승하차지 수만큼의 번호 마커를 만든다', () {
    final result = overlay(
      route(stops: [stop(3), stop(4), stop(5)], roadPath: road),
    );

    expect(result.polylines, hasLength(1));
    expect(result.polylines.single.points, road);
    expect(result.polylines.single.dashed, isFalse);
    expect(result.markers, hasLength(3));
    expect(result.markers.every((m) => m.kind == MapMarkerKind.stop), isTrue);
  });

  test('마커의 번호는 목록 순번이 아니라 승하차지의 실제 seq 다', () {
    final result = overlay(
      route(stops: [stop(3), stop(4), stop(5)], roadPath: road),
    );

    expect(result.markers.map((m) => m.seq), [3, 4, 5]);
  });

  test('road_path 가 비면 표시 승하차지를 점선으로 잇는다', () {
    final result = overlay(route(stops: [stop(3), stop(4), stop(5)]));

    expect(result.polylines, hasLength(1));
    expect(result.polylines.single.dashed, isTrue);
    expect(result.polylines.single.points, [
      for (final seq in [3, 4, 5])
        (lat: 37.5 + seq / 1000, lng: 126.7 + seq / 1000),
    ]);
  });

  test('road_path 가 1점뿐이어도 2점 미만이라 점선으로 잇는다', () {
    final result = overlay(
      route(stops: [stop(3), stop(4)], roadPath: [(lat: 37.5, lng: 126.7)]),
    );

    expect(result.polylines.single.dashed, isTrue);
    expect(result.polylines.single.points, hasLength(2));
  });

  test('응답에 없는 승하차지는 그리지 않는다 — 번호가 3~5 인 응답이면 1·2·6 은 없다', () {
    final result = overlay(
      route(stops: [stop(3), stop(4), stop(5)], roadPath: road),
    );

    expect(result.markers.map((m) => m.seq), isNot(contains(1)));
    expect(result.markers.map((m) => m.seq), isNot(contains(2)));
    expect(result.markers.map((m) => m.seq), isNot(contains(6)));
    expect(result.markers, hasLength(3));
  });

  test('좌표가 없는 승하차지는 마커도 점선 꼭짓점도 만들지 않는다', () {
    const noCoords = RouteStop(
      stopId: 'academy',
      seq: 5,
      name: '학원',
      address: null,
      lat: null,
      lng: null,
    );
    final result = overlay(route(stops: [stop(3), stop(4), noCoords]));

    expect(result.markers.map((m) => m.seq), [3, 4]);
    expect(result.polylines.single.points, hasLength(2));
  });

  test('점이 2개 미만이면 선을 그리지 않는다', () {
    final result = overlay(route(stops: [stop(4)]));

    expect(result.polylines, isEmpty);
    expect(result.markers, hasLength(1));
  });

  test('내 승하차지 마커는 강조 표시와 "내 승하차지" 이름표를 달고 다른 마커는 달지 않는다', () {
    final result = overlay(
      route(stops: [stop(3), stop(4), stop(5)], roadPath: road),
    );

    final mine = result.markers.where((m) => m.mine).toList();
    expect(mine.map((m) => m.seq), [4]);
    expect(mine.single.label, '내 승하차지');
    expect(
      result.markers.where((m) => !m.mine).every((m) => m.label == null),
      isTrue,
    );
  });

  test('도착 시각(arrived_at)이 있는 승하차지만 지나간 모양이다', () {
    final result = overlay(
      route(
        stops: [
          stop(3, arrivedAt: DateTime.utc(2026, 10, 5, 3, 9)),
          stop(4),
          stop(5),
        ],
        roadPath: road,
      ),
    );

    expect(result.markers.map((m) => m.stopState), [
      MapStopState.passed,
      MapStopState.upcoming,
      MapStopState.upcoming,
    ]);
  });

  test('운행 중이면 아직 안 지난 첫 승하차지가 "다음" 모양이다', () {
    final result = overlay(
      route(
        stops: [
          stop(2, arrivedAt: DateTime.utc(2026, 10, 5, 3, 5)),
          stop(3),
          stop(4),
        ],
        roadPath: road,
      ),
      markNext: true,
    );

    expect(result.markers.map((m) => m.stopState), [
      MapStopState.passed,
      MapStopState.next,
      MapStopState.upcoming,
    ]);
  });

  test('운행이 끝났으면 같은 경로선을 "지나온 구간" 색으로 그리고 마커도 그대로 남긴다', () {
    final stops = [
      stop(3, arrivedAt: DateTime.utc(2026, 10, 5, 3, 9)),
      stop(4, arrivedAt: DateTime.utc(2026, 10, 5, 3, 15)),
    ];
    final result = overlay(route(stops: stops, roadPath: road), ended: true);

    expect(result.polylines, hasLength(1));
    expect(result.polylines.single.passed, isTrue);
    expect(result.markers.map((m) => m.seq), [3, 4]);
    expect(
      result.markers.every((m) => m.stopState == MapStopState.passed),
      isTrue,
    );
  });

  test('종료 전에는 경로선이 "지나온 구간" 색이 아니다', () {
    final result = overlay(route(stops: [stop(3), stop(4)], roadPath: road));

    expect(result.polylines.single.passed, isFalse);
  });

  test('그릴 것이 하나도 없으면 비어 있다고 알린다', () {
    expect(overlay(route(stops: const [])).isEmpty, isTrue);
    expect(overlay(route(stops: [stop(3)])).isEmpty, isFalse);
  });

  group('RouteDetail.fromJson — road_path · fallback_used', () {
    Map<String, dynamic> json({Map<String, dynamic> extra = const {}}) => {
      'run_id': 'r-1',
      'bus_no': '2호차',
      'depart_time': '2026-10-05T03:20:00Z',
      'confirmed': true,
      'driver': {'name': null},
      'escort': {'name': null, 'phone': null},
      'my_stop_id': 's4',
      'stops': <Map<String, dynamic>>[],
      ...extra,
    };

    test('좌표열과 직선 근사 표식을 읽는다', () {
      final detail = RouteDetail.fromJson(
        json(
          extra: {
            'road_path': [
              {'lat': 37.5, 'lng': 126.7},
              {'lat': 37.6, 'lng': 126.8},
            ],
            'fallback_used': true,
          },
        ),
      );

      expect(detail.roadPath, [
        (lat: 37.5, lng: 126.7),
        (lat: 37.6, lng: 126.8),
      ]);
      expect(detail.fallbackUsed, isTrue);
    });

    test('서버가 아직 두 필드를 안 주면 빈 경로 · 근사 아님으로 읽는다', () {
      final detail = RouteDetail.fromJson(json());

      expect(detail.roadPath, isEmpty);
      expect(detail.fallbackUsed, isFalse);
    });
  });
}
