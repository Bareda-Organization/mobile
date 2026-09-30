import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_screen.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

import '../../support/manager_run_fixture.dart';

/// R33 M1 — 위치 송신이 화면이 아니라 앱 전역이 되어(`position_transmitter.dart`) 운행 화면을 나가도
/// 송신이 멈추지 않는다. R32 M15·M16 이 넣은 "나갈까요?" 확인 창은 이유가 사라져 없앴다 — 운행 중이어도
/// 뒤로가기는 바로 나간다.
class _NeverResolvingTokenStorage extends TokenStorage {
  _NeverResolvingTokenStorage()
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
  Future<void> openDrive(WidgetTester tester, RunStatus status) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
          positionSourceProvider.overrideWithValue(_NoSample()),
          routeProvider.overrideWith(
            (ref) async => const RouteResponse(stops: []),
          ),
          selectedRunIdProvider.overrideWith((ref) => 'run-1'),
          currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
          todayRunsProvider.overrideWith(
            (ref) async => [managerRunFixture(status: status)],
          ),
          driveModeRosterProvider.overrideWith((ref) async => _emptyRoster),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const DriveModeScreen()),
                ),
                child: const Text('HOME_MARKER'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('HOME_MARKER'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> pressBack(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }

  testWidgets('운행 중에도 뒤로가기는 확인 없이 바로 나간다', (tester) async {
    await openDrive(tester, RunStatus.moving);

    await pressBack(tester);

    expect(find.text('운행 화면을 나갈까요?'), findsNothing);
    expect(find.byType(DriveModeScreen), findsNothing);
    expect(find.text('HOME_MARKER'), findsOneWidget);
  });

  testWidgets('운행 중이 아니어도 바로 나간다', (tester) async {
    await openDrive(tester, RunStatus.confirmed);

    await pressBack(tester);

    expect(find.text('운행 화면을 나갈까요?'), findsNothing);
    expect(find.byType(DriveModeScreen), findsNothing);
  });
}
