import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/map/map_surface.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/domain/route_repository.dart';
import 'package:manager_app/features/route_map/presentation/route_map_screen.dart';

/// ⚠ **이 파일이 검증하지 못하는 것** — 실제 네이버 지도 SDK 초기화
/// (`NaverMapAdapter._initSdk` → `FlutterNaverMap().init()`)는 플랫폼
/// 채널을 필요로 하는데, 위젯 시험 환경에는 그 채널이 없다. `init()` 은
/// `MissingPluginException` 으로 항상 실패하고 화면은 "지도를 불러오지
/// 못했습니다" 자리표시만 그린다 — 이 경로는 위젯 시험으로 도달이
/// 원천적으로 불가능하다(같은 결론을 `parent-app` 의
/// `naver_map_adapter_dispose_test.dart` 가 이미 문서화했다).
///
/// 그래서 이 파일은 지도 SDK 를 아예 거치지 않고, [MapSurface] 가 받는
/// `camera`·`markers` 인자를 직접 검사해 **화면이 무엇을 그리라고
/// 지시했는지**만 확인한다 — "지도가 실제로 떴다" 는 여전히 검증하지
/// 못한다.
class _FakeRouteRepository implements RouteRepository {
  new(this.response);

  final RouteResponse response;

  @override
  Future<RouteResponse> fetchRoute(String runId) async => response;
}

/// `roster_screen_test.dart` 의 `_NeverResolvingTokenStorage` 와 같은
/// 대역 — `ManagerChannelBanner` 가 여는 실제 `ManagerRunChannelController`
/// 를 `connecting` 상태로 고정해, 시험이 실제 WebSocket 연결을 시도하지
/// 않게 한다.
class _NeverResolvingTokenStorage extends TokenStorage {
  new()
    : super(
        accessTokenKey: 'test_access_token',
        refreshTokenKey: 'test_refresh_token',
      );

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;
}

RouteStop _stop({
  required String stopId,
  required int seq,
  double lat = 37.5,
  double lng = 127,
}) {
  return RouteStop(stopId: stopId, seq: seq, name: '$seq번', lat: lat, lng: lng);
}

Widget _wrap(List<Override> overrides) {
  return ProviderScope(
    overrides: [
      tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
      ...overrides,
    ],
    child: const MaterialApp(home: RouteMapScreen()),
  );
}

void main() {
  const runId = 'run-1';

  List<Override> overridesFor(RouteResponse response) => [
    selectedRunIdProvider.overrideWith((ref) => runId),
    routeRepositoryProvider.overrideWithValue(_FakeRouteRepository(response)),
  ];

  testWidgets('선택된 운행이 없으면 안내만 보이고 지도를 그리지 않는다', (tester) async {
    await tester.pumpWidget(
      _wrap([selectedRunIdProvider.overrideWith((ref) => null)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('선택된 운행이 없습니다 — 홈에서 운행을 선택하세요'), findsOneWidget);
    expect(find.byType(MapSurface), findsNothing);
  });

  testWidgets('승하차지가 빈 배열이면 안내만 보이고 지도를 그리지 않는다', (tester) async {
    await tester.pumpWidget(
      _wrap(overridesFor(const RouteResponse(stops: []))),
    );
    await tester.pumpAndSettle();

    expect(find.text('표시할 승하차지가 없습니다'), findsOneWidget);
    expect(find.byType(MapSurface), findsNothing);
  });

  testWidgets('마커는 stops[] 전부를 stop 종류로만 찍는다(bus 마커 없음)', (tester) async {
    final response = RouteResponse(
      stops: [
        _stop(stopId: 's1', seq: 1),
        _stop(stopId: 's2', seq: 2),
        _stop(stopId: 's3', seq: 3),
      ],
    );

    // ⚠ `pumpAndSettle()` 을 쓰지 않는다 — `MapSurface` 뒤의
    // `NaverMapAdapter` 가 SDK 초기화 중 `CircularProgressIndicator`
    // (무한 반복 애니메이션)를 그리므로 settle 이 영원히 끝나지 않는다
    // (parent-app `naver_map_adapter_dispose_test.dart` 와 같은 이유).
    // `routeProvider`(FutureProvider)가 값을 내놓는 데 필요한 만큼만
    // pump 한다 — `MapSurface` 에 어떤 인자가 넘어갔는지만 보면 되므로
    // SDK 초기화 완료까지 기다릴 필요가 없다.
    await tester.pumpWidget(_wrap(overridesFor(response)));
    await tester.pump();
    await tester.pump();

    final surface = tester.widget<MapSurface>(find.byType(MapSurface));
    expect(surface.markers, hasLength(3));
    expect(
      surface.markers.every((m) => m.kind == MapMarkerKind.stop),
      isTrue,
      reason:
          'route_map_screen.dart 의 판정(F4-B 2단계 M2) — 매니저 채널에는 '
          'position 이 없어 실시간 버스 위치를 알 길이 없다. bus 마커가 '
          '하나라도 섞이면 그 판정이 깨진 것이다.',
    );
    expect(surface.markers.map((m) => m.id), containsAll(['s1', 's2', 's3']));
  });

  // 2026-09-23 사용자 지시 — 정차지 핀 안에 순번을 넣는다. 순번은 화면이 넘겨야 어댑터가 그린다.
  // 정차지 id 와 순번을 일부러 어긋나게 둔다 — 순서대로 1·2·3 을 매겨 넣는 구현이 통과하지 않게.
  testWidgets('정차지 마커는 그 정차지의 순번을 싣는다', (tester) async {
    final response = RouteResponse(
      stops: [
        _stop(stopId: 's1', seq: 3),
        _stop(stopId: 's2', seq: 1),
        _stop(stopId: 's3', seq: 2),
      ],
    );

    await tester.pumpWidget(_wrap(overridesFor(response)));
    await tester.pump();
    await tester.pump();

    final surface = tester.widget<MapSurface>(find.byType(MapSurface));
    expect(
      {for (final m in surface.markers) m.id: m.seq},
      {'s1': 3, 's2': 1, 's3': 2},
    );
  });

  testWidgets('카메라 중심은 current_stop 을 최우선한다', (tester) async {
    final response = RouteResponse(
      stops: [_stop(stopId: 's1', seq: 1, lat: 10, lng: 10)],
      currentStop: _stop(stopId: 'c', seq: 0, lat: 20, lng: 20),
      nextStop: _stop(stopId: 'n', seq: 2, lat: 30, lng: 30),
    );

    await tester.pumpWidget(_wrap(overridesFor(response)));
    await tester.pump();
    await tester.pump();

    final surface = tester.widget<MapSurface>(find.byType(MapSurface));
    expect(surface.camera.lat, 20);
    expect(surface.camera.lng, 20);
  });

  testWidgets('current_stop 이 없으면 next_stop 을 중심으로 한다', (tester) async {
    final response = RouteResponse(
      stops: [_stop(stopId: 's1', seq: 1, lat: 10, lng: 10)],
      nextStop: _stop(stopId: 'n', seq: 2, lat: 30, lng: 30),
    );

    await tester.pumpWidget(_wrap(overridesFor(response)));
    await tester.pump();
    await tester.pump();

    final surface = tester.widget<MapSurface>(find.byType(MapSurface));
    expect(surface.camera.lat, 30);
    expect(surface.camera.lng, 30);
  });

  testWidgets('current_stop·next_stop 이 둘 다 없으면 첫 승하차지를 중심으로 한다', (
    tester,
  ) async {
    final response = RouteResponse(
      stops: [
        _stop(stopId: 's1', seq: 1, lat: 40, lng: 40),
        _stop(stopId: 's2', seq: 2, lat: 50, lng: 50),
      ],
    );

    await tester.pumpWidget(_wrap(overridesFor(response)));
    await tester.pump();
    await tester.pump();

    final surface = tester.widget<MapSurface>(find.byType(MapSurface));
    expect(surface.camera.lat, 40);
    expect(surface.camera.lng, 40);
  });

  testWidgets('skipped_notice 가 있으면 안내 배너를 보여준다', (tester) async {
    final response = RouteResponse(
      stops: [_stop(stopId: 's1', seq: 1)],
      skippedNotice: '2곳이 미경유로 표시됩니다',
    );

    await tester.pumpWidget(_wrap(overridesFor(response)));
    await tester.pump();
    await tester.pump();

    expect(find.text('2곳이 미경유로 표시됩니다'), findsOneWidget);
  });

  // F06-11 — 운행 화면 지도 패널과 같은 지도를 두 벌 관리하면서 노선 지도 쪽에 도로 경로·근사 안내·
  // 카메라 맞춤이 빠져 있었다. 두 화면이 같은 지도 면을 쓰므로 같은 것을 보여야 한다.
  testWidgets('road_path 가 2점 이상이면 도로 경로 선을 그린다', (tester) async {
    final response = RouteResponse(
      stops: [
        _stop(stopId: 's1', seq: 1),
        _stop(stopId: 's2', seq: 2),
      ],
      roadPath: const [
        (lat: 37.501, lng: 127.001),
        (lat: 37.502, lng: 127.002),
      ],
    );

    await tester.pumpWidget(_wrap(overridesFor(response)));
    await tester.pump();
    await tester.pump();

    final surface = tester.widget<MapSurface>(find.byType(MapSurface));
    expect(surface.polylines, hasLength(1));
    expect(surface.polylines.single.points, response.roadPath);
  });

  testWidgets('fallback_used 면 근사 경로라고 알린다', (tester) async {
    final response = RouteResponse(
      stops: [_stop(stopId: 's1', seq: 1)],
      roadPath: const [
        (lat: 37.501, lng: 127.001),
        (lat: 37.502, lng: 127.002),
      ],
      fallbackUsed: true,
    );

    await tester.pumpWidget(_wrap(overridesFor(response)));
    await tester.pump();
    await tester.pump();

    expect(find.text('근사 경로 — 실제 도로와 다를 수 있습니다'), findsOneWidget);
  });

  testWidgets('카메라를 노선이 보이게 맞추도록 지시한다', (tester) async {
    await tester.pumpWidget(
      _wrap(overridesFor(RouteResponse(stops: [_stop(stopId: 's1', seq: 1)]))),
    );
    await tester.pump();
    await tester.pump();

    final surface = tester.widget<MapSurface>(find.byType(MapSurface));
    expect(surface.fitToContent, isTrue);
  });

  // R39 Ruling 400 — 경유 지점은 번호 없는 waypoint 마커이고, 승하차지 번호는 경유 지점을 뺀 연속 번호다.
  // 서버 seq 는 경유 지점 자리(2)를 비운 채 1·3·4 로 오지만 명단은 경유 지점을 싣지 않는다(Ruling 398).
  testWidgets('경유 지점은 waypoint 마커로 찍고 승하차지 번호는 경유 지점을 건너뛰어 연속으로 매긴다', (
    tester,
  ) async {
    final response = RouteResponse(
      stops: [
        _stop(stopId: 's1', seq: 1),
        const RouteStop(
          stopId: 'w2',
          seq: 2,
          name: '주유소',
          lat: 37.55,
          lng: 127.05,
          isWaypoint: true,
        ),
        _stop(stopId: 's3', seq: 3),
        _stop(stopId: 's4', seq: 4),
      ],
    );

    await tester.pumpWidget(_wrap(overridesFor(response)));
    await tester.pump();
    await tester.pump();

    final surface = tester.widget<MapSurface>(find.byType(MapSurface));
    final waypoints = surface.markers.where(
      (m) => m.kind == MapMarkerKind.waypoint,
    );
    expect(waypoints, hasLength(1));
    expect(waypoints.single.seq, isNull);
    expect(
      {
        for (final m in surface.markers.where(
          (m) => m.kind == MapMarkerKind.stop,
        ))
          m.id: m.seq,
      },
      {'s1': 1, 's3': 2, 's4': 3},
    );
  });

  testWidgets('오늘 서지 않는(skipped) 승하차지는 마커가 skipped 를 켠다', (tester) async {
    final response = RouteResponse(
      stops: [
        const RouteStop(
          stopId: 's1',
          seq: 1,
          name: '1번',
          lat: 37.5,
          lng: 127,
          change: RouteStopChange.skipped,
        ),
        _stop(stopId: 's2', seq: 2),
      ],
    );

    await tester.pumpWidget(_wrap(overridesFor(response)));
    await tester.pump();
    await tester.pump();

    final surface = tester.widget<MapSurface>(find.byType(MapSurface));
    expect(
      {for (final m in surface.markers) m.id: m.skipped},
      {'s1': true, 's2': false},
    );
  });

  // 시안 `route-map` — 지도가 화면 전체를 쓰고 머리줄은 그 위에 뜬다. 아래에는 범례 카드가 있다.
  testWidgets('지도는 화면 맨 위부터 그려지고 머리줄이 그 위에 뜬다', (tester) async {
    final response = RouteResponse(stops: [_stop(stopId: 's1', seq: 1)]);

    await tester.pumpWidget(_wrap(overridesFor(response)));
    await tester.pump();
    await tester.pump();

    expect(tester.getTopLeft(find.byType(MapSurface)).dy, 0);
    expect(find.text('노선 지도'), findsOneWidget);
  });

  testWidgets('아래 범례 카드가 지난 곳 · 다음 · 추가 · 정차 안 함과 안내용 선이라는 문구를 알린다', (
    tester,
  ) async {
    final response = RouteResponse(stops: [_stop(stopId: 's1', seq: 1)]);

    await tester.pumpWidget(_wrap(overridesFor(response)));
    await tester.pump();
    await tester.pump();

    for (final label in ['지난 곳', '다음', '추가', '정차 안 함']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('지도 선은 안내용이고, 실제 길은 기사 판단이에요.'), findsOneWidget);
  });

  testWidgets('범례 카드에 skipped_notice 가 함께 들어간다', (tester) async {
    final response = RouteResponse(
      stops: [_stop(stopId: 's1', seq: 1)],
      skippedNotice: '5 한빛빌라 — 오늘 탑승 학생이 없어 정차하지 않아요.',
    );

    await tester.pumpWidget(_wrap(overridesFor(response)));
    await tester.pump();
    await tester.pump();

    final legendCard = find.ancestor(
      of: find.text('정차 안 함'),
      matching: find.byType(BaraedaCard),
    );
    expect(
      find.descendant(
        of: legendCard,
        matching: find.text('5 한빛빌라 — 오늘 탑승 학생이 없어 정차하지 않아요.'),
      ),
      findsOneWidget,
    );
  });
}
