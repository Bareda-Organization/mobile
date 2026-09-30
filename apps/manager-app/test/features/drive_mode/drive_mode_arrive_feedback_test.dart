import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/launcher/device_launchers.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
import 'package:manager_app/features/drive_mode/data/models/start_run_result.dart';
import 'package:manager_app/features/drive_mode/domain/drive_mode_repository.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_screen.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

import '../../support/manager_run_fixture.dart';

/// 도착 처리 요청을 기록하고 항상 성공(마지막이 아닌 승하차지)으로 답한다.
class _ArriveRecorder implements DriveModeRepository {
  final arrivedStopIds = <String>[];

  @override
  Future<ArriveStopResult> arriveStop({
    required String runId,
    required String stopId,
  }) async {
    arrivedStopIds.add(stopId);
    return ArriveStopResult(
      arrivedAt: DateTime(2026, 10, 1, 8, 5),
      isFinal: false,
      runStatus: RunStatus.moving,
      finishPending: false,
      remaining: const [],
    );
  }

  @override
  Future<StartRunResult> startRun(String runId) => throw UnimplementedError();
}

/// 위치 권한·서비스 상태를 시험이 정하는 가짜 소스 — 좌표는 없다.
class _FixedAvailabilitySource implements PositionSource {
  _FixedAvailabilitySource(this.availability);

  @override
  final PositionAvailability availability;

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

/// 토큰을 영원히 기다려 운행 채널 연결이 시작되지 않게 한다 — 이 시험의 대상이 아니다.
class _NeverResolvingTokenStorage extends TokenStorage {
  _NeverResolvingTokenStorage()
    : super(accessTokenKey: 'a', refreshTokenKey: 'r');

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;
}

RosterStop _stop(int seq, {bool arrived = false}) => RosterStop(
  stopId: 's$seq',
  seq: seq,
  name: '$seq번 승하차지',
  arrivedAt: arrived ? DateTime(2026, 10, 1, 8, 1) : null,
  students: const [],
);

void main() {
  Future<({_ArriveRecorder repository, List<String> settingsOpened})> pumpDrive(
    WidgetTester tester, {
    List<RosterStop>? stops,
    PositionAvailability availability = PositionAvailability.available,
  }) async {
    final repository = _ArriveRecorder();
    final settingsOpened = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
          positionSourceProvider.overrideWithValue(
            _FixedAvailabilitySource(availability),
          ),
          settingsOpenerProvider.overrideWithValue((page) async {
            settingsOpened.add(page.name);
            return true;
          }),
          routeProvider.overrideWith(
            (ref) async => const RouteResponse(stops: []),
          ),
          selectedRunIdProvider.overrideWith((ref) => 'run-1'),
          currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
          todayRunsProvider.overrideWith(
            (ref) async => [managerRunFixture(status: RunStatus.moving)],
          ),
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
              stops: stops ?? [_stop(1), _stop(2), _stop(3)],
            ),
          ),
          driveModeRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: DriveModeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    return (repository: repository, settingsOpened: settingsOpened);
  }

  group('B2 #15 중간 승하차지 도착 처리 피드백', () {
    testWidgets('도착 처리에 성공하면 "N번 … 도착 처리됨" 을 알린다 (R46)', (tester) async {
      await pumpDrive(tester);

      await tester.tap(find.text('도착 처리'));
      await tester.pump();
      await tester.pump();

      expect(find.text('1번 1번 승하차지 도착 처리됨'), findsOneWidget);
    });

    testWidgets('성공 직후 2초 안의 두 번째 누름은 다음 승하차지를 처리하지 않는다 (R46)', (tester) async {
      final harness = await pumpDrive(tester);

      await tester.tap(find.text('도착 처리'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('도착 처리'), warnIfMissed: false);
      await tester.pump();

      expect(harness.repository.arrivedStopIds, ['s1']);

      // 잠금이 풀리면 다시 눌린다.
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.text('도착 처리'));
      await tester.pump();
      expect(harness.repository.arrivedStopIds, ['s1', 's1']);
    });
  });

  group('B2 #19 위치 권한 배너 [설정 열기]', () {
    testWidgets('권한이 없으면 [설정 열기] 가 앱 설정을 연다 (R46)', (tester) async {
      final harness = await pumpDrive(
        tester,
        availability: PositionAvailability.permissionDenied,
      );
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.text('설정 열기'));
      await tester.pump();

      expect(harness.settingsOpened, ['app']);
    });

    testWidgets('위치 서비스가 꺼져 있으면 [설정 열기] 가 위치 설정을 연다 (R46)', (tester) async {
      final harness = await pumpDrive(
        tester,
        availability: PositionAvailability.serviceDisabled,
      );
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.text('설정 열기'));
      await tester.pump();

      expect(harness.settingsOpened, ['location']);
    });

    testWidgets('정상이면 [설정 열기] 가 없다', (tester) async {
      await pumpDrive(tester);
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('설정 열기'), findsNothing);
    });
  });
}
