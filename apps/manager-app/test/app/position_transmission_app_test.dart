import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/app.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/app/router.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/constants/position_constants.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
import 'package:manager_app/features/drive_mode/data/models/start_run_result.dart';
import 'package:manager_app/features/drive_mode/domain/drive_mode_repository.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/position/data/models/position_request.dart';
import 'package:manager_app/features/position/domain/position_repository.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

import '../support/fake_token_storage.dart';
import '../support/manager_run_fixture.dart';

/// R33 M1 — 위치 송신은 화면이 아니라 앱 전역이다. 운행 중(`moving`)인 기사 회차면 어느 화면에서든
/// 2초마다 보내고, 운행 종료(마지막 도착 처리 응답)·로그아웃에 멈추며, 송신기는 하나다.
/// 앱 전체(`BaraedaManagerApp`)를 띄워 실제 라우터로 화면을 오간다.
class _FakeSource implements PositionSource {
  int startCalls = 0;
  int stopCalls = 0;

  @override
  PositionAvailability get availability => PositionAvailability.available;

  @override
  PositionSample? sample() =>
      PositionSample(lat: 37.5, lng: 127, recordedAt: DateTime(2020));

  @override
  void start() => startCalls++;

  @override
  void stop() => stopCalls++;

  @override
  Future<PositionSample?> sampleOnce({
    Duration timeout = const Duration(seconds: 5),
  }) async => null;
}

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

class _StubAuthRepository implements AuthRepository {
  @override
  Future<void> logout() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 마지막 승하차지 도착 처리 응답(`is_final`) — 하원 잔류로 서버 회차는 아직 `moving` 인 채다.
class _FinalArriveRepository implements DriveModeRepository {
  @override
  Future<ArriveStopResult> arriveStop({
    required String runId,
    required String stopId,
  }) async => ArriveStopResult(
    arrivedAt: DateTime(2026, 9, 30, 8, 30),
    isFinal: true,
    runStatus: RunStatus.moving,
    finishPending: true,
    remaining: const [],
  );

  @override
  Future<StartRunResult> startRun(String runId) => throw UnimplementedError();
}

const Duration _interval = PositionConstants.transmissionInterval;

void main() {
  late _FakeSource source;
  late _RecordingPositionRepository repository;

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    UserRole role = UserRole.driver,
    RunStatus status = RunStatus.moving,
  }) async {
    source = _FakeSource();
    repository = _RecordingPositionRepository();
    final overrides = <Override>[
      tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
      currentUserRoleProvider.overrideWith((ref) => role),
      currentAccountStatusProvider.overrideWith(
        (ref) => AccountStatus.active,
      ),
      authRepositoryProvider.overrideWithValue(_StubAuthRepository()),
      driveModeRepositoryProvider.overrideWithValue(_FinalArriveRepository()),
      selectedRunIdProvider.overrideWith((ref) => 'run-1'),
      todayRunsProvider.overrideWith(
        (ref) async => [managerRunFixture(status: status)],
      ),
      routeProvider.overrideWith(
        (ref) async => const RouteResponse(stops: []),
      ),
      driveModeRosterProvider.overrideWith(
        (ref) async => const RosterResponse(
          runId: 'run-1',
          busNo: '3호차',
          direction: RunDirection.toAcademy,
          counts: RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
          stops: [
            RosterStop(
              stopId: 's1',
              seq: 1,
              name: '학원 앞',
              students: [],
            ),
          ],
        ),
      ),
      positionSourceProvider.overrideWithValue(source),
      positionRepositoryProvider.overrideWithValue(repository),
    ];
    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const BaraedaManagerApp()),
    );
    await tester.pumpAndSettle();
    // 컨테이너는 위젯 트리가 소유한다 — 시험이 끝나 트리가 걷힐 때 송신 타이머도 함께 정리된다.
    return ProviderScope.containerOf(
      tester.element(find.byType(BaraedaManagerApp)),
    );
  }

  /// 화면을 옮긴다 — 실제 라우터로 간다.
  Future<void> goTo(
    WidgetTester tester,
    ProviderContainer container,
    String location,
  ) async {
    container.read(routerProvider).go(location);
    await tester.pumpAndSettle();
  }

  testWidgets('운행 화면을 나가도 위치 송신이 계속된다', (tester) async {
    final container = await pumpApp(tester);

    await goTo(tester, container, AppRoutes.driveMode);
    await tester.pump(_interval);
    expect(repository.calls, hasLength(1));

    await goTo(tester, container, AppRoutes.home);
    await tester.pump(_interval);
    await tester.pump(_interval);

    expect(
      repository.calls,
      hasLength(3),
      reason: '운행 화면을 나간 뒤에도 2초마다 송신이 이어져야 한다',
    );
  });

  testWidgets('운행 화면을 한 번도 열지 않아도 운행 중인 기사 회차면 홈에서도 송신한다', (tester) async {
    await pumpApp(tester);

    await tester.pump(_interval);
    await tester.pump(_interval);

    expect(repository.calls, hasLength(2));
  });

  testWidgets('운행 화면을 다시 열어도 송신기는 하나다 — 주기마다 요청은 1건', (tester) async {
    final container = await pumpApp(tester);

    await goTo(tester, container, AppRoutes.driveMode);
    await goTo(tester, container, AppRoutes.home);
    await goTo(tester, container, AppRoutes.driveMode);
    final before = repository.calls.length;

    await tester.pump(_interval);
    await tester.pump(_interval);
    await tester.pump(_interval);

    expect(repository.calls.length - before, 3);
    expect(source.stopCalls, 0, reason: '화면을 오간다고 위치 스트림을 껐다 켜지 않는다');
  });

  testWidgets('로그아웃하면 송신이 멈춘다', (tester) async {
    await pumpApp(tester);
    await tester.pump(_interval);
    expect(repository.calls, hasLength(1));

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('로그아웃'),
      ),
    );
    await tester.pumpAndSettle();
    final afterLogout = repository.calls.length;

    await tester.pump(_interval * 3);

    expect(repository.calls.length, afterLogout);
    expect(source.stopCalls, greaterThan(0));
  });

  testWidgets('마지막 도착 처리 응답이 오면 회차가 아직 moving 이어도 송신이 멈춘다', (tester) async {
    final container = await pumpApp(tester);
    await goTo(tester, container, AppRoutes.driveMode);
    await tester.pump(_interval);
    expect(repository.calls, hasLength(1));

    await tester.tap(find.text('학원 앞 도착 처리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('도착했습니다'));
    await tester.pumpAndSettle();
    final afterArrive = repository.calls.length;

    await tester.pump(_interval * 3);

    expect(repository.calls.length, afterArrive);
  });

  testWidgets('동승자는 운행 중이어도 어느 화면에서든 보내지 않는다', (tester) async {
    await pumpApp(tester, role: UserRole.escort);

    await tester.pump(_interval * 3);

    expect(repository.calls, isEmpty);
    expect(source.startCalls, 0);
  });

  testWidgets('운행 중이 아닌 회차는 보내지 않는다', (tester) async {
    await pumpApp(tester, status: RunStatus.confirmed);

    await tester.pump(_interval * 3);

    expect(repository.calls, isEmpty);
  });
}
