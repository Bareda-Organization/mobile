import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/me_provider.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
import 'package:manager_app/features/drive_mode/data/models/start_run_result.dart';
import 'package:manager_app/features/drive_mode/domain/drive_mode_repository.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/run_ready_screen.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

import '../../support/manager_run_fixture.dart';

/// 운행 시작 요청을 세는 가짜 — 이 시험들의 관심사는 "언제 요청이 나가는가" 하나다.
class _CountingDriveRepository implements DriveModeRepository {
  new({this.failure});

  final Failure? failure;
  int startCalls = 0;

  @override
  Future<StartRunResult> startRun(String runId) async {
    startCalls++;
    // Failure 는 Exception/Error 를 상속하지 않는다.
    // ignore: only_throw_errors
    if (failure != null) throw failure!;
    return StartRunResult(
      runStatus: RunStatus.moving,
      startedAt: DateTime(2026, 10, 3, 12, 20),
    );
  }

  @override
  Future<SendOutcome<ArriveStopResult>> arriveStop({
    required String runId,
    required String stopId,
  }) => throw UnimplementedError('이 파일의 시험 대상이 아니다');
}

class _FixedClock implements Clock {
  const new(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

const _roster = RosterResponse(
  runId: 'run-1',
  busNo: '2호차',
  direction: RunDirection.toAcademy,
  counts: RosterCounts(boarded: 0, waiting: 4, noShow: 0, absentN: 2),
  stops: [],
);

/// 출발 12:20 · 시작 창 12:10 ~ 12:30(`managerRunFixture` 기본값은 출발 ±10분).
final _depart = DateTime(2026, 10, 3, 12, 20);

void main() {
  Widget wrap(
    DateTime now,
    _CountingDriveRepository repo, {
    bool routeFails = false,
    ManagerRun? run,
  }) {
    final router = GoRouter(
      initialLocation: AppRoutes.runReady,
      routes: [
        GoRoute(
          path: AppRoutes.runReady,
          builder: (_, _) => const RunReadyScreen(),
        ),
        GoRoute(
          path: AppRoutes.driveMode,
          builder: (_, _) => const Text('DRIVE_MARKER'),
        ),
        GoRoute(
          path: AppRoutes.rosterView,
          builder: (_, _) => const Text('ROSTER_VIEW_MARKER'),
        ),
      ],
    );
    final overrides = <Override>[
      clockProvider.overrideWithValue(_FixedClock(now)),
      currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
      selectedRunIdProvider.overrideWith((ref) => 'run-1'),
      driveModeRunProvider.overrideWithValue(
        run ??
            managerRunFixture(
              busNo: '2호차',
              departTime: _depart,
            ),
      ),
      driveModeRepositoryProvider.overrideWithValue(repo),
      positionSourceProvider.overrideWithValue(
        const UnavailablePositionSource(),
      ),
      meProvider.overrideWith(
        (ref) async => const MeResponse(
          accountId: '1',
          loginId: 'driverA2',
          name: '박정훈',
          phone: '010-0000-0000',
          role: AccountRole.driver,
          status: AccountStatus.active,
        ),
      ),
      if (routeFails) ...[
        // Failure 는 Exception/Error 를 상속하지 않는다.
        // ignore: only_throw_errors
        routeProvider.overrideWith((ref) => throw const Failure.unknown()),
      ] else
        routeProvider.overrideWith(
          (ref) async => const RouteResponse(stops: []),
        ),
      driveModeRosterProvider.overrideWith((ref) async => _roster),
    ];
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(routerConfig: router),
    );
  }

  VoidCallback? startPressed(WidgetTester tester) => tester
      .widget<BaraedaButton>(find.widgetWithText(BaraedaButton, '운행 시작'))
      .onPressed;

  // L1(UF-D-02) — 기사는 운행을 시작하기 전에도 승하차지 명단(조회 전용)을 열어 볼 수 있다.
  testWidgets('운행 시작 전에도 [명단 보기] 로 조회 전용 명단을 연다', (tester) async {
    await tester.pumpWidget(
      wrap(DateTime(2026, 10, 3, 12, 2), _CountingDriveRepository()),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(BaraedaButton, '명단 보기'));
    await tester.tap(find.widgetWithText(BaraedaButton, '명단 보기'));
    await tester.pumpAndSettle();

    expect(find.text('ROSTER_VIEW_MARKER'), findsOneWidget);
  });

  testWidgets('시작 가능 시간(출발 ±10분) 안이면 [운행 시작] 이 켜지고 시간대가 보인다', (tester) async {
    final repo = _CountingDriveRepository();
    await tester.pumpWidget(wrap(DateTime(2026, 10, 3, 12, 14), repo));
    await tester.pumpAndSettle();

    expect(startPressed(tester), isNotNull);
    expect(find.text('시작 가능 12:10 ~ 12:30 (출발 ±10분)'), findsOneWidget);
  });

  testWidgets('시작 가능 시간 전에는 [운행 시작] 이 꺼지고 언제부터인지 이유가 보인다', (tester) async {
    final repo = _CountingDriveRepository();
    await tester.pumpWidget(wrap(DateTime(2026, 10, 3, 12, 2), repo));
    await tester.pumpAndSettle();

    expect(startPressed(tester), isNull);
    expect(find.textContaining('12:10 부터 시작할 수 있어요'), findsOneWidget);

    // 꺼진 단추를 눌러도 확인 창도 요청도 없다.
    await tester.tap(find.widgetWithText(BaraedaButton, '운행 시작'));
    await tester.pumpAndSettle();
    expect(find.text('운행을 시작할까요?'), findsNothing);
    expect(repo.startCalls, 0);
  });

  testWidgets('시작 가능 시간이 지나면 [운행 시작] 이 꺼지고 지났다고 알린다', (tester) async {
    await tester.pumpWidget(
      wrap(DateTime(2026, 10, 3, 12, 45), _CountingDriveRepository()),
    );
    await tester.pumpAndSettle();

    expect(startPressed(tester), isNull);
    expect(find.text('운행 시작 가능 시간(출발 ±10분)이 지났어요'), findsOneWidget);
  });

  testWidgets('노선을 못 받으면 [운행 시작] 이 꺼지고 이유와 다시 시도가 보인다(M20)', (tester) async {
    final repo = _CountingDriveRepository();
    await tester.pumpWidget(
      wrap(DateTime(2026, 10, 3, 12, 14), repo, routeFails: true),
    );
    await tester.pumpAndSettle();

    expect(startPressed(tester), isNull);
    expect(find.text('확정 노선을 불러오지 못했어요'), findsOneWidget);
    expect(find.text('노선을 받으면 시작할 수 있어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('[운행 시작] 은 확인 창에서 [시작하기] 를 눌러야만 요청이 나간다', (tester) async {
    final repo = _CountingDriveRepository();
    await tester.pumpWidget(wrap(DateTime(2026, 10, 3, 12, 14), repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(BaraedaButton, '운행 시작'));
    await tester.pumpAndSettle();
    // 확인 창이 떠 있는 동안에는 요청이 없다.
    expect(find.text('운행을 시작할까요?'), findsOneWidget);
    expect(repo.startCalls, 0);

    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();
    expect(repo.startCalls, 1);
    expect(find.text('DRIVE_MARKER'), findsOneWidget);
  });

  testWidgets('확인 창에서 [닫기] 를 누르면 요청이 나가지 않는다', (tester) async {
    final repo = _CountingDriveRepository();
    await tester.pumpWidget(wrap(DateTime(2026, 10, 3, 12, 14), repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(BaraedaButton, '운행 시작'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();

    expect(repo.startCalls, 0);
    expect(find.text('DRIVE_MARKER'), findsNothing);
  });

  // M4(Ruling 340) — 취소된 회차에 시작을 시도하면 서버가 409 RUN_CANCELED 로 거절한다. 문구를 보인다.
  testWidgets('409 RUN_CANCELED 면 문구를 보이고 운행 화면으로 가지 않는다', (tester) async {
    final repo = _CountingDriveRepository(
      failure: const ApiFailure(
        statusCode: 409,
        code: 'RUN_CANCELED',
        message: '취소된 회차입니다',
      ),
    );
    await tester.pumpWidget(wrap(DateTime(2026, 10, 3, 12, 14), repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(BaraedaButton, '운행 시작'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();

    expect(find.text('취소된 회차입니다'), findsOneWidget);
    expect(find.text('DRIVE_MARKER'), findsNothing);
  });
}
