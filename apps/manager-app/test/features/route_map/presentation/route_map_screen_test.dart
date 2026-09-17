import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
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
  _FakeRouteRepository(this.response);

  final RouteResponse response;

  @override
  Future<RouteResponse> fetchRoute(String runId) async => response;
}

/// `roster_screen_test.dart` 의 `_NeverResolvingTokenStorage` 와 같은
/// 대역 — `ManagerChannelBanner` 가 여는 실제 `ManagerRunChannelController`
/// 를 `connecting` 상태로 고정해, 시험이 실제 WebSocket 연결을 시도하지
/// 않게 한다.
class _NeverResolvingTokenStorage extends TokenStorage {
  _NeverResolvingTokenStorage()
    : super(accessTokenKey: 'test_access_token', refreshTokenKey: 'test_refresh_token');

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
    await tester.pumpWidget(_wrap(overridesFor(const RouteResponse(stops: []))));
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
}
