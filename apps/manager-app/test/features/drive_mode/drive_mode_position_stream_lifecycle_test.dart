import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_screen.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/position/data/models/position_request.dart';
import 'package:manager_app/features/position/domain/position_repository.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

/// LOC-01 백그라운드 송신(`Ruling 360`) — 실제 GeolocatorPositionSource 를
/// `_FakeGeolocatorPlatform`(`position_source_test.dart` 와 같은 발상)
/// 뒤에 세워, 화면 진입·운행 종료·dispose 가 **위치 스트림 구독 자체**를
/// 열고 닫는지 잰다. 위 두 시험 파일(`drive_mode_position_transmission_test`
/// ·`drive_mode_wakelock_test`)의 가짜 `PositionSource` 는 sample() 호출
/// 횟수만 재서 이 구독 개폐를 볼 수 없다 — 별도 시험이 필요한 이유.
class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  LocationPermission checkPermissionResult = LocationPermission.whileInUse;
  bool serviceEnabled = true;

  /// 지금 살아 있는 위치 스트림 구독 수 — 포그라운드 서비스(Android)·
  /// 백그라운드 갱신(iOS)이 실제로 켜졌는지의 대리 지표.
  int listenerCount = 0;

  late final StreamController<Position> _controller =
      StreamController<Position>.broadcast(
        onListen: () => listenerCount++,
        onCancel: () => listenerCount--,
      );

  @override
  Future<LocationPermission> checkPermission() async => checkPermissionResult;

  @override
  Future<LocationPermission> requestPermission() async => checkPermissionResult;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      _controller.stream;
}

class _FixedClock implements Clock {
  const _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

class _NoopPositionRepository implements PositionRepository {
  @override
  Future<void> sendPosition({
    required String runId,
    required PositionRequest request,
  }) async {}
}

Widget _wrap(Widget child, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

const _emptyRoster = RosterResponse(
  runId: 'run-1',
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  counts: RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
  stops: [],
);

void main() {
  const runId = 'run-1';
  final now = DateTime(2026, 9, 26, 8);

  ManagerRun run(RunStatus runStatus) => ManagerRun(
    runId: runId,
    busNo: '3호차',
    direction: RunDirection.toAcademy,
    departTime: now.add(const Duration(minutes: 10)),
    origin: '기점',
    destination: '학원',
    estDurationMin: 30,
    runStatus: runStatus,
    confirmed: true,
    startWindowFrom: now.subtract(const Duration(minutes: 5)),
    startWindowTo: now.add(const Duration(minutes: 5)),
    addedCount: 0,
    removedCount: 0,
    ackRequired: false,
    roleInRun: UserRole.driver,
  );

  /// [positionSourceProvider] 를 오버라이드하지 않는다 — `di.dart` 의
  /// 기본 provider 가 만드는 실제 [GeolocatorPositionSource] 를 그대로
  /// 쓰고, 그 밑을 [_FakeGeolocatorPlatform] 으로 갈아 끼운다. 화면이
  /// [PositionSource.start]/[stop] 을 실제로 부르는지까지 이 경로로만
  /// 확인할 수 있다.
  List<Override> baseOverrides({
    required UserRole role,
    required ManagerRun currentRun,
  }) => [
    clockProvider.overrideWithValue(_FixedClock(now)),
    currentUserRoleProvider.overrideWith((ref) => role),
    selectedRunIdProvider.overrideWith((ref) => runId),
    driveModeRunProvider.overrideWithValue(currentRun),
    // F06-12 — 송신 대상은 오늘 회차 목록에서 고른다(화면이 고른 회차가 아니다).
    todayRunsProvider.overrideWith((ref) async {
      final run = ref.watch(driveModeRunProvider);
      return run == null ? <ManagerRun>[] : [run];
    }),
    // R32 M1 — 운행 화면이 노선을 조회한다. 실제 서버로 나가지 않게 빈 노선으로 막는다.
    routeProvider.overrideWith((ref) async => const RouteResponse(stops: [])),
    driveModeRosterProvider.overrideWith((ref) async => _emptyRoster),
    positionRepositoryProvider.overrideWithValue(_NoopPositionRepository()),
  ];

  testWidgets('기사가 운행 화면에 들어가면 위치 스트림 구독이 1이 된다', (tester) async {
    final platform = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = platform;

    await tester.pumpWidget(
      _wrap(
        const DriveModeScreen(),
        baseOverrides(role: UserRole.driver, currentRun: run(RunStatus.moving)),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(platform.listenerCount, 1);
  });

  testWidgets('운행이 끝나면(finished) 위치 스트림 구독이 0이 된다', (tester) async {
    final platform = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = platform;
    final runState = StateProvider<ManagerRun>((ref) => run(RunStatus.moving));
    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(_FixedClock(now)),
        currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
        selectedRunIdProvider.overrideWith((ref) => runId),
        driveModeRunProvider.overrideWith((ref) => ref.watch(runState)),
        // F06-12 — 송신 대상은 오늘 회차 목록에서 고른다(화면이 고른 회차가 아니다).
        todayRunsProvider.overrideWith((ref) async {
          final run = ref.watch(driveModeRunProvider);
          return run == null ? <ManagerRun>[] : [run];
        }),
        // R32 M1 — 운행 화면이 노선을 조회한다. 실제 서버로 나가지 않게 빈 노선으로 막는다.
        routeProvider.overrideWith(
          (ref) async => const RouteResponse(stops: []),
        ),
        driveModeRosterProvider.overrideWith((ref) async => _emptyRoster),
        positionRepositoryProvider.overrideWithValue(
          _NoopPositionRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DriveModeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(platform.listenerCount, 1);

    container.read(runState.notifier).state = run(RunStatus.finished);
    // 회차 목록(송신 대상의 출처)이 비동기로 다시 계산된다 — 그 결과가 반영될 때까지 기다린다.
    await tester.pump();
    await tester.pump();

    expect(platform.listenerCount, 0);
  });

  // R33 M1 — 위치 스트림도 화면이 아니라 운행 상태에 묶인다. 옛 시험(`화면이 dispose 되면
  // 위치 스트림 구독이 0이 된다`)은 화면을 나가면 구독이 끊기는 결함을 고정하고 있었다 — 반대로
  // 화면이 사라져도 구독이 1로 남는 것을 지킨다.
  testWidgets('화면이 dispose 되어도 위치 스트림 구독은 1로 남는다', (tester) async {
    final platform = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = platform;
    final overrides = baseOverrides(
      role: UserRole.driver,
      currentRun: run(RunStatus.moving),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(home: DriveModeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(platform.listenerCount, 1);

    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const SizedBox.shrink()),
    );
    await tester.pump();

    expect(platform.listenerCount, 1);
  });

  testWidgets('동승자가 운행 화면에 들어가도 위치 스트림 구독은 열리지 않는다', (tester) async {
    final platform = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = platform;

    await tester.pumpWidget(
      _wrap(
        const DriveModeScreen(),
        baseOverrides(
          role: UserRole.escort,
          currentRun: run(RunStatus.moving),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(platform.listenerCount, 0);
  });
}
