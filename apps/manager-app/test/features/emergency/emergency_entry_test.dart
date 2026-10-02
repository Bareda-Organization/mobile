import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_screen.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/home/presentation/home_screen.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/roster/presentation/roster_screen.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

import '../../support/manager_run_fixture.dart';

/// R32 M2 — 비상 신고는 기사·동승자 모두, 확정 이후면 운행 중이 아니어도, 홈·운행·명단
/// 세 화면 머리말에서 닿아야 한다(M-15 · UF-X-08). 지금까지 `/emergency` 는 라우트만 있고
/// 앱 어디서도 가는 길이 없었다.
const _emergencyMarker = 'EMERGENCY_SCREEN_MARKER';

class _NeverResolvingTokenStorage extends TokenStorage {
  new()
    : super(
        accessTokenKey: 'test_access_token',
        refreshTokenKey: 'test_refresh_token',
      );

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;
}

class _NoSample implements PositionSource {
  @override
  PositionAvailability get availability => PositionAvailability.available;

  @override
  PositionSample? sample() => null;

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

const _emptyRoster = RosterResponse(
  runId: 'run-1',
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  counts: RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
  stops: [],
);

void main() {
  Widget wrap(String initial, List<Override> overrides) {
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (_, _) => const ManagerHomeScreen(),
        ),
        GoRoute(
          path: AppRoutes.driveMode,
          builder: (_, _) => const DriveModeScreen(),
        ),
        GoRoute(
          path: AppRoutes.roster,
          builder: (_, _) => const RosterScreen(),
        ),
        GoRoute(
          path: AppRoutes.emergency,
          builder: (_, _) => const Text(_emergencyMarker),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
        positionSourceProvider.overrideWithValue(_NoSample()),
        routeProvider.overrideWith(
          (ref) async => const RouteResponse(stops: []),
        ),
        driveModeRosterProvider.overrideWith((ref) async => _emptyRoster),
        rosterProvider.overrideWith((ref) async => _emptyRoster),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  String? selectedRunId(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  ).read(selectedRunIdProvider);

  for (final role in [UserRole.driver, UserRole.escort]) {
    testWidgets('홈 — ${role.name} 도 확정된 회차가 하나면 비상 버튼이 그 회차의 신고 화면으로 간다', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(AppRoutes.home, [
          todayRunsProvider.overrideWith((ref) async => [managerRunFixture()]),
          currentUserRoleProvider.overrideWith((ref) => role),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('비상'));
      await tester.pumpAndSettle();

      expect(find.text(_emergencyMarker), findsOneWidget);
      expect(selectedRunId(tester), 'run-1');
    });
  }

  testWidgets('홈 — 확정 전 회차뿐이면 신고 화면으로 가지 않고 이유를 알린다', (tester) async {
    await tester.pumpWidget(
      wrap(AppRoutes.home, [
        todayRunsProvider.overrideWith(
          (ref) async => [
            managerRunFixture(status: RunStatus.idle, confirmed: false),
          ],
        ),
        currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('비상'));
    await tester.pumpAndSettle();

    expect(find.text(_emergencyMarker), findsNothing);
    expect(find.text('확정된 운행이 있을 때 비상 신고를 보낼 수 있습니다'), findsOneWidget);
  });

  testWidgets('홈 — 종료된 회차에는 신고하지 않는다', (tester) async {
    await tester.pumpWidget(
      wrap(AppRoutes.home, [
        todayRunsProvider.overrideWith(
          (ref) async => [managerRunFixture(status: RunStatus.finished)],
        ),
        currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('비상'));
    await tester.pumpAndSettle();

    expect(find.text(_emergencyMarker), findsNothing);
  });

  testWidgets('홈 — 신고 가능한 회차가 여럿이면 고르게 하고 고른 회차로 간다', (tester) async {
    await tester.pumpWidget(
      wrap(AppRoutes.home, [
        todayRunsProvider.overrideWith(
          (ref) async => [
            managerRunFixture(),
            managerRunFixture(
              runId: 'run-2',
              busNo: '5호차',
              status: RunStatus.moving,
            ),
          ],
        ),
        currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('비상'));
    await tester.pumpAndSettle();
    expect(find.text('어느 운행의 비상입니까?'), findsOneWidget);
    expect(find.text(_emergencyMarker), findsNothing);

    await tester.tap(find.textContaining('5호차').last);
    await tester.pumpAndSettle();

    expect(find.text(_emergencyMarker), findsOneWidget);
    expect(selectedRunId(tester), 'run-2');
  });

  testWidgets('운행 화면 — 운행 시작 전(확정)에도 머리말에 비상 버튼이 있고 신고 화면으로 간다', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(AppRoutes.driveMode, [
        selectedRunIdProvider.overrideWith((ref) => 'run-1'),
        todayRunsProvider.overrideWith((ref) async => [managerRunFixture()]),
        currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
      ]),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('비상'));
    await tester.pumpAndSettle();

    expect(find.text(_emergencyMarker), findsOneWidget);
  });

  testWidgets('명단 화면 — 동승자 머리말에 비상 버튼이 있고 신고 화면으로 간다', (tester) async {
    await tester.pumpWidget(
      wrap(AppRoutes.roster, [
        selectedRunIdProvider.overrideWith((ref) => 'run-1'),
        todayRunsProvider.overrideWith((ref) async => [managerRunFixture()]),
        currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('비상'));
    await tester.pumpAndSettle();

    expect(find.text(_emergencyMarker), findsOneWidget);
  });
}
