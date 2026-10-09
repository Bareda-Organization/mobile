import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/constants/position_constants.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/manager_run_channel.dart';
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

/// 시각을 고정하는 가짜 시계 — `drive_mode_screen_test.dart` 와 같은 패턴.
class _FixedClock implements Clock {
  const new(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

/// 항상 같은 좌표 스냅샷을 돌려주는 가짜 위치 소스. `recordedAt` 을
/// 시험이 고정하는 "지금"과 **다른 값**으로 둬서, 화면이 전송 시각을
/// 새로 채우는 것이 아니라 이 값을 그대로 옮기는지 구별한다(§4.12).
class _FakePositionSource implements PositionSource {
  new(
    this._sample, {
    this.availability = PositionAvailability.available,
  });

  final PositionSample? _sample;
  int callCount = 0;

  @override
  final PositionAvailability availability;

  @override
  PositionSample? sample() {
    callCount++;
    return _sample;
  }

  @override
  Future<void> recheck() async {}

  @override
  void start() {}

  @override
  void stop() {}

  @override
  Future<PositionSample?> sampleOnce({
    Duration timeout = const Duration(seconds: 5),
  }) async => null;
}

/// 실제 서버를 부르지 않고 `sendPosition` 호출을 그대로 기록하는 가짜
/// 리포지토리 — 타이머가 실제로 도는지, 몇 번 도는지를 이걸로 잰다.
class _RecordingPositionRepository implements PositionRepository {
  final List<PositionRequest> calls = [];

  @override
  Future<void> sendPosition({
    required String runId,
    required PositionRequest request,
  }) async {
    calls.add(request);
  }
}

/// 서버가 회차를 더 이상 운행 중으로 보지 않는다고 답하는 가짜 — 모든 전송이
/// `409 RUN_NOT_MOVING`(API_SPEC §4.12)으로 거절된다. 호출은 그대로 기록한다.
class _NotMovingPositionRepository extends _RecordingPositionRepository {
  @override
  Future<void> sendPosition({
    required String runId,
    required PositionRequest request,
  }) async {
    await super.sendPosition(runId: runId, request: request);
    await Future<void>.error(
      const Failure.api(
        statusCode: 409,
        code: 'RUN_NOT_MOVING',
        message: '운행 중 상태가 아닙니다',
      ),
    );
  }
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

ManagerRun _managerRun({
  required RunStatus runStatus,
  required DateTime now,
}) {
  return ManagerRun(
    runId: 'run-1',
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
}

void main() {
  const runId = 'run-1';
  final now = DateTime(2026, 9, 12, 8);
  // 시험이 고정하는 "지금"과 다른 값 — 서버로 나가는 recorded_at 이
  // clockProvider(전송 시각)가 아니라 [PositionSample.recordedAt](단말
  // 측정 시각)에서 온 것인지 이 값 하나로 구별한다.
  final recordedAt = DateTime(2020);

  List<Override> baseOverrides({
    required UserRole role,
    required RunStatus runStatus,
    required _FakePositionSource positionSource,
    required _RecordingPositionRepository positionRepository,
    void Function()? onRunsLoad,
  }) => [
    clockProvider.overrideWithValue(_FixedClock(now)),
    currentUserRoleProvider.overrideWith((ref) => role),
    selectedRunIdProvider.overrideWith((ref) => runId),
    driveModeRunProvider.overrideWithValue(
      _managerRun(runStatus: runStatus, now: now),
    ),
    // F06-12 — 송신 대상은 오늘 회차 목록에서 고른다(화면이 고른 회차가 아니다).
    todayRunsProvider.overrideWith((ref) async {
      onRunsLoad?.call();
      final run = ref.watch(driveModeRunProvider);
      return run == null ? <ManagerRun>[] : [run];
    }),
    // R32 M1 — 운행 화면이 노선을 조회한다. 실제 서버로 나가지 않게 빈 노선으로 막는다.
    routeProvider.overrideWith((ref) async => const RouteResponse(stops: [])),
    driveModeRosterProvider.overrideWith((ref) async => _emptyRoster),
    positionSourceProvider.overrideWithValue(positionSource),
    positionRepositoryProvider.overrideWithValue(positionRepository),
  ];

  testWidgets(
    '기사·이동 중 상태면 PositionConstants.transmissionInterval 주기로 위치를 전송한다',
    (
      tester,
    ) async {
      final source = _FakePositionSource(
        PositionSample(lat: 37.5, lng: 127, recordedAt: recordedAt),
      );
      final repository = _RecordingPositionRepository();
      const interval = PositionConstants.transmissionInterval;

      // 이 시험은 dispose() 가 아니라 "이동 중 → 그 외 상태" 전이에서
      // 타이머가 멎는 별도 정지 경로(_syncPositionTransmission 의
      // else 분기)를 본다. 그 경로를 시험 도중에 직접 밟으려면 회차
      // 값을 실행 중에 바꿀 수 있어야 해서, 고정 오버라이드 대신
      // StateProvider 로 감싼 컨테이너를 쓴다 — 그래야 이 시험이
      // "dispose 시 정지" 시험(아래)과 서로 다른 경로를 검증하게 되어,
      // dispose() 의 정지 호출만 지웠을 때 이 시험까지 함께 실패하지
      // 않는다(끝나기 전에 스스로 타이머를 정지시켜 두기 때문).
      final runState = StateProvider<ManagerRun?>(
        (ref) => _managerRun(runStatus: RunStatus.moving, now: now),
      );
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
          positionSourceProvider.overrideWithValue(source),
          positionRepositoryProvider.overrideWithValue(repository),
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

      // 주기가 지나기 전에는 아직 전송이 없어야 "0초마다"가 아님을
      // 함께 확인한다. 값을 상수에서 읽으므로 주기가 바뀌어도 이 시험은
      // 그대로 유효하다 — 값 자체를 고정하는 것은 아래 별도 시험의 몫.
      await tester.pump(interval - const Duration(milliseconds: 1));
      expect(repository.calls, isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.calls, hasLength(1));
      // 서버로 나가는 recorded_at 은 전송 시각(clockProvider 의 `now`)이
      // 아니라 위치 소스가 준 단말 측정 시각 그대로다.
      expect(repository.calls.single.recordedAt, recordedAt);

      // 주기 타이머임을 확인 — 한 주기를 더 지나면 두 번째 전송이 있다.
      await tester.pump(interval);
      expect(repository.calls, hasLength(2));

      // 시험이 끝나기 전에 이동 중 상태를 벗어나 타이머를 스스로
      // 정지시킨다 — dispose() 의 정지 호출과는 무관한 경로다.
      container.read(runState.notifier).state = _managerRun(
        runStatus: RunStatus.confirmed,
        now: now,
      );
      await tester.pump();
      final callsAfterStop = repository.calls.length;
      await tester.pump(interval * 2);
      expect(repository.calls.length, callsAfterStop);
    },
  );

  // R46-FIXCONN C-10 — 위치 POST 성공은 이 앱에서 서버에 다시 닿았다는
  // 신호다 — 끊긴 실시간 연결을 바로 다시 붙이게 알린다.
  testWidgets('위치 전송이 성공할 때마다 서버 도달 신호를 올린다', (tester) async {
    final source = _FakePositionSource(
      PositionSample(lat: 37.5, lng: 127, recordedAt: recordedAt),
    );
    final repository = _RecordingPositionRepository();
    const interval = PositionConstants.transmissionInterval;
    await tester.pumpWidget(
      ProviderScope(
        overrides: baseOverrides(
          role: UserRole.driver,
          runStatus: RunStatus.moving,
          positionSource: source,
          positionRepository: repository,
        ),
        child: const MaterialApp(home: DriveModeScreen()),
      ),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DriveModeScreen)),
    );
    expect(container.read(serverReachedProvider), 0);

    await tester.pump(interval);
    await tester.pump();
    expect(container.read(serverReachedProvider), 1);

    await tester.pump(interval);
    await tester.pump();
    expect(container.read(serverReachedProvider), 2);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // §4.12 — 409 RUN_NOT_MOVING 은 서버가 이 회차를 운행 중이 아니라고 답한 것이다.
  // 같은 회차로 다음 주기에 또 보내면 같은 409 가 반복되므로 그 회차 송신을 멈춘다.
  testWidgets('409 RUN_NOT_MOVING 을 받은 뒤 다음 주기에 다시 보내지 않는다', (tester) async {
    final source = _FakePositionSource(
      PositionSample(lat: 37.5, lng: 127, recordedAt: recordedAt),
    );
    final repository = _NotMovingPositionRepository();
    const interval = PositionConstants.transmissionInterval;

    await tester.pumpWidget(
      ProviderScope(
        overrides: baseOverrides(
          role: UserRole.driver,
          runStatus: RunStatus.moving,
          positionSource: source,
          positionRepository: repository,
        ),
        child: const MaterialApp(home: DriveModeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(interval);
    await tester.pump();
    expect(repository.calls, hasLength(1));

    await tester.pump(interval * 3);
    expect(
      repository.calls,
      hasLength(1),
      reason: '409 뒤에도 같은 회차로 계속 보내면 안 된다',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('409 RUN_NOT_MOVING 을 받으면 오늘 회차 목록을 다시 받는다', (tester) async {
    final source = _FakePositionSource(
      PositionSample(lat: 37.5, lng: 127, recordedAt: recordedAt),
    );
    final repository = _NotMovingPositionRepository();
    const interval = PositionConstants.transmissionInterval;
    var runsLoads = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: baseOverrides(
          role: UserRole.driver,
          runStatus: RunStatus.moving,
          positionSource: source,
          positionRepository: repository,
          onRunsLoad: () {
            runsLoads++;
          },
        ),
        child: const MaterialApp(home: DriveModeScreen()),
      ),
    );
    await tester.pump();
    final loadsBefore = runsLoads;

    await tester.pump(interval);
    await tester.pump();

    expect(repository.calls, hasLength(1));
    expect(
      runsLoads,
      greaterThan(loadsBefore),
      reason: '409 뒤에는 오늘 회차 목록을 새로 받아 서버의 운행 상태와 맞춘다',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('위치 전송 주기 상수는 2초로 고정한다 (2026-09-14 사용자 결정)', () {
    // ⚠ 값 자체를 하드코딩해 대조한다 — 위 위젯 시험처럼 상수를 그대로
    // 읽어 쓰면 상수가 조용히 바뀌어도 아무 시험도 잡지 못한다. 방송량이
    // 이 값에 산술적으로 비례하므로(COMMON-B2 §2), 바뀌면 이 시험이
    // 먼저 깨져 리뷰를 강제해야 한다.
    expect(
      PositionConstants.transmissionInterval,
      const Duration(seconds: 2),
    );
  });

  // R33 M1 — 위치 송신은 화면이 아니라 앱 전역이다. 옛 시험(`화면이 dispose 되면 위치 송신
  // 타이머가 멈춘다`, F4 이월 3번)은 "화면을 나가면 송신이 끊기는" 결함을 고정하고 있었다 —
  // 반대로, 화면이 사라져도 송신이 이어지는 것을 지킨다. 화면만 걷고 ProviderScope 는 그대로 둔다
  // (같은 overrides 목록 · 같은 위치의 ProviderScope 라 상태가 유지된다).
  testWidgets('화면이 dispose 되어도 위치 송신은 계속된다', (tester) async {
    final source = _FakePositionSource(
      PositionSample(lat: 37.5, lng: 127, recordedAt: recordedAt),
    );
    final repository = _RecordingPositionRepository();
    const interval = PositionConstants.transmissionInterval;
    final overrides = baseOverrides(
      role: UserRole.driver,
      runStatus: RunStatus.moving,
      positionSource: source,
      positionRepository: repository,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(home: DriveModeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(interval);
    expect(repository.calls, hasLength(1));

    // 운행 화면을 걷어낸다 — DriveModeScreen 의 State.dispose() 가 호출된다.
    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const SizedBox.shrink()),
    );
    await tester.pump();
    final callsAtDispose = repository.calls.length;

    await tester.pump(interval * 3);
    expect(
      repository.calls.length,
      callsAtDispose + 3,
      reason: '송신은 화면이 아니라 운행 상태에 묶여 있어 화면이 사라져도 2초마다 이어져야 한다',
    );
  });

  testWidgets('동승자면 이동 중이어도 위치를 전송하지 않는다', (tester) async {
    final source = _FakePositionSource(
      PositionSample(lat: 37.5, lng: 127, recordedAt: recordedAt),
    );
    final repository = _RecordingPositionRepository();

    await tester.pumpWidget(
      _wrap(
        const DriveModeScreen(),
        baseOverrides(
          role: UserRole.escort,
          runStatus: RunStatus.moving,
          positionSource: source,
          positionRepository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));

    expect(repository.calls, isEmpty);
  });

  testWidgets('기사여도 이동 중이 아니면 위치를 전송하지 않는다', (tester) async {
    final source = _FakePositionSource(
      PositionSample(lat: 37.5, lng: 127, recordedAt: recordedAt),
    );
    final repository = _RecordingPositionRepository();

    await tester.pumpWidget(
      _wrap(
        const DriveModeScreen(),
        baseOverrides(
          role: UserRole.driver,
          runStatus: RunStatus.confirmed,
          positionSource: source,
          positionRepository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));

    expect(repository.calls, isEmpty);
  });

  testWidgets('위치 권한이 거부됐으면 화면에 안내를 보여주고 전송은 건너뛴다', (tester) async {
    final source = _FakePositionSource(
      null,
      availability: PositionAvailability.permissionDenied,
    );
    final repository = _RecordingPositionRepository();

    await tester.pumpWidget(
      _wrap(
        const DriveModeScreen(),
        baseOverrides(
          role: UserRole.driver,
          runStatus: RunStatus.moving,
          positionSource: source,
          positionRepository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(PositionConstants.transmissionInterval);

    expect(
      find.textContaining('위치 권한이 꺼져 있어요'),
      findsOneWidget,
    );
    expect(repository.calls, isEmpty);
  });

  testWidgets('위치 서비스가 꺼져 있으면 화면에 안내를 보여주고 전송은 건너뛴다', (tester) async {
    final source = _FakePositionSource(
      null,
      availability: PositionAvailability.serviceDisabled,
    );
    final repository = _RecordingPositionRepository();

    await tester.pumpWidget(
      _wrap(
        const DriveModeScreen(),
        baseOverrides(
          role: UserRole.driver,
          runStatus: RunStatus.moving,
          positionSource: source,
          positionRepository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(PositionConstants.transmissionInterval);

    expect(
      find.textContaining('기기 위치 서비스가 꺼져 있어요'),
      findsOneWidget,
    );
    expect(repository.calls, isEmpty);
  });
}
