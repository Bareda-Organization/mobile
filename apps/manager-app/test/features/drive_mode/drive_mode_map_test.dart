import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/constants/position_constants.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/map/map_surface.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_screen.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/position/data/models/position_request.dart';
import 'package:manager_app/features/position/domain/position_repository.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

/// M1(R32) — 운행 화면 가운데 지도. 실제 네이버 SDK 는 위젯 시험에서 그려지지 않으므로
/// `route_map_screen_test.dart` 와 같이 [MapSurface] 가 받은 인자(핀·선·버스·카메라)만 본다.
/// ⚠ 지도가 화면에 실제로 떴는지는 이 시험이 못 본다 — 병합 뒤 시뮬레이터로 확인한다.

class _FixedClock implements Clock {
  const _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

class _FakePositionSource implements PositionSource {
  _FakePositionSource(this._sample);

  final PositionSample? _sample;

  @override
  PositionAvailability get availability => PositionAvailability.available;

  @override
  PositionSample? sample() => _sample;

  @override
  void start() {}

  @override
  void stop() {}

  @override
  Future<PositionSample?> sampleOnce({
    Duration timeout = const Duration(seconds: 5),
  }) async => null;
}

class _NoopPositionRepository implements PositionRepository {
  @override
  Future<void> sendPosition({
    required String runId,
    required PositionRequest request,
  }) async {}
}

/// `ManagerChannelBanner` 가 실제 WebSocket 을 열지 않게 연결 중에 고정한다.
class _NeverResolvingTokenStorage extends TokenStorage {
  _NeverResolvingTokenStorage()
    : super(
        accessTokenKey: 'test_access_token',
        refreshTokenKey: 'test_refresh_token',
      );

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;
}

RouteStop _routeStop(int seq, {double? lat, double? lng}) => RouteStop(
  stopId: 's$seq',
  seq: seq,
  name: '$seq번 승하차지',
  lat: lat ?? 37.5 + seq * 0.001,
  lng: lng ?? 127.0 + seq * 0.001,
);

RosterStop _rosterStop(int seq) => RosterStop(
  stopId: 's$seq',
  seq: seq,
  name: '$seq번 승하차지',
  students: const [],
);

ManagerRun _run(DateTime now, RunStatus status) => ManagerRun(
  runId: 'run-1',
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  departTime: now.add(const Duration(minutes: 10)),
  origin: '기점',
  destination: '학원',
  estDurationMin: 30,
  runStatus: status,
  confirmed: true,
  startWindowFrom: now.subtract(const Duration(minutes: 5)),
  startWindowTo: now.add(const Duration(minutes: 5)),
  addedCount: 0,
  removedCount: 0,
  ackRequired: false,
);

void main() {
  final now = DateTime(2026, 9, 30, 8);
  final stops = [for (var i = 1; i <= 4; i++) _routeStop(i)];

  List<Override> overrides({
    RouteResponse? route,
    PositionSample? sample,
    RunStatus status = RunStatus.moving,
  }) => [
    clockProvider.overrideWithValue(_FixedClock(now)),
    tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
    currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
    selectedRunIdProvider.overrideWith((ref) => 'run-1'),
    driveModeRunProvider.overrideWithValue(_run(now, status)),
    driveModeRosterProvider.overrideWith(
      (ref) async => RosterResponse(
        runId: 'run-1',
        busNo: '3호차',
        direction: RunDirection.toAcademy,
        counts: const RosterCounts(
          boarded: 0,
          waiting: 0,
          noShow: 0,
          absentN: 0,
        ),
        stops: [for (var i = 1; i <= 4; i++) _rosterStop(i)],
      ),
    ),
    routeProvider.overrideWith(
      (ref) async => route ?? RouteResponse(stops: stops),
    ),
    positionSourceProvider.overrideWithValue(_FakePositionSource(sample)),
    positionRepositoryProvider.overrideWithValue(_NoopPositionRepository()),
  ];

  Future<void> pumpScreen(
    WidgetTester tester,
    List<Override> overrides,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(home: DriveModeScreen()),
      ),
    );
    // MapSurface 뒤 어댑터가 SDK 초기화 중 무한 애니메이션을 그려 pumpAndSettle 은 쓰지 않는다.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('운행 화면 가운데는 개발용 빈 상자가 아니라 지도 면이다', (tester) async {
    await pumpScreen(tester, overrides());

    expect(find.textContaining('지도 자리'), findsNothing);
    expect(find.textContaining('다음 라운드'), findsNothing);
    expect(find.byType(MapSurface), findsOneWidget);
  });

  testWidgets('승하차지 핀 수는 노선의 승하차지 수와 같고 순번을 싣는다', (tester) async {
    await pumpScreen(tester, overrides());

    final surface = tester.widget<MapSurface>(find.byType(MapSurface));
    final pins = surface.markers.where((m) => m.kind == MapMarkerKind.stop);
    expect(pins, hasLength(stops.length));
    expect(
      {for (final m in pins) m.id: m.seq},
      {
        's1': 1,
        's2': 2,
        's3': 3,
        's4': 4,
      },
    );
  });

  testWidgets('기사 단말이 잰 좌표가 있으면 그 자리에 버스 마커를 찍는다', (tester) async {
    final sample = PositionSample(lat: 37.51, lng: 127.02, recordedAt: now);
    await pumpScreen(tester, overrides(sample: sample));
    // 위치 송신 주기가 한 번 돌아야 화면이 좌표를 본다.
    await tester.pump(PositionConstants.transmissionInterval);
    await tester.pump();

    final surface = tester.widget<MapSurface>(find.byType(MapSurface));
    final buses = surface.markers.where((m) => m.kind == MapMarkerKind.bus);
    expect(buses, hasLength(1));
    expect(buses.single.lat, 37.51);
    expect(buses.single.lng, 127.02);
  });

  testWidgets('좌표를 아직 못 쟀으면 버스 마커를 지어내지 않는다', (tester) async {
    await pumpScreen(tester, overrides());
    await tester.pump(PositionConstants.transmissionInterval);
    await tester.pump();

    final surface = tester.widget<MapSurface>(find.byType(MapSurface));
    expect(surface.markers.where((m) => m.kind == MapMarkerKind.bus), isEmpty);
  });

  // 지도를 늘리다 대형 버튼이 화면 밖으로 밀린 적이 없는지 — 작은 화면에서 본다.
  testWidgets('360×640 화면에서도 도착 처리 대형 버튼이 화면 안에 보인다', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreen(tester, overrides());

    final button = find.text('1번 승하차지 도착 처리');
    expect(button, findsOneWidget);
    final rect = tester.getRect(button);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(640));
    expect(
      tester.getSize(find.byType(MapSurface)).height,
      greaterThan(120),
      reason: '지도가 너무 작으면 있으나 마나다',
    );
  });

  // 서버가 road_path·fallback_used 를 얹기 전 응답과 얹은 응답 둘 다 견뎌야 한다(조율자 결정).
  testWidgets('road_path 가 2점 이상이면 도로 경로 선을 그린다', (tester) async {
    final route = RouteResponse(
      stops: stops,
      roadPath: const [
        (lat: 37.501, lng: 127.001),
        (lat: 37.502, lng: 127.002),
        (lat: 37.503, lng: 127.003),
      ],
    );
    await pumpScreen(tester, overrides(route: route));

    final surface = tester.widget<MapSurface>(find.byType(MapSurface));
    expect(surface.polylines, hasLength(1));
    expect(surface.polylines.single.points, route.roadPath);
    expect(find.text('근사 경로 — 실제 도로와 다를 수 있습니다'), findsNothing);
  });

  testWidgets('road_path 가 없거나 1점이면 선 없이 핀만 그린다', (tester) async {
    await pumpScreen(tester, overrides());
    var surface = tester.widget<MapSurface>(find.byType(MapSurface));
    expect(surface.polylines, isEmpty);
    expect(surface.markers, isNotEmpty);

    await pumpScreen(
      tester,
      overrides(
        route: RouteResponse(
          stops: stops,
          roadPath: const [(lat: 37.501, lng: 127.001)],
        ),
      ),
    );
    surface = tester.widget<MapSurface>(find.byType(MapSurface));
    expect(surface.polylines, isEmpty);
  });

  testWidgets('fallback_used 면 근사 경로라고 알린다', (tester) async {
    final route = RouteResponse(
      stops: stops,
      roadPath: const [
        (lat: 37.501, lng: 127.001),
        (lat: 37.502, lng: 127.002),
      ],
      fallbackUsed: true,
    );
    await pumpScreen(tester, overrides(route: route));

    expect(find.text('근사 경로 — 실제 도로와 다를 수 있습니다'), findsOneWidget);
  });

  testWidgets('카메라를 노선·버스가 전부 보이게 맞추도록 지시한다', (tester) async {
    await pumpScreen(tester, overrides());

    final surface = tester.widget<MapSurface>(find.byType(MapSurface));
    expect(surface.fitToContent, isTrue);
  });
}
