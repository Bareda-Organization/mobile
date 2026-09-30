import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
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

/// R32 M5·M6 — 기사 운행 화면. ① 운행 시작 · 마지막 승하차지 도착(= 운행 종료)은 확인 창을 거치고
/// 취소하면 요청이 나가지 않는다 ② 남은 승하차지를 조회 전용으로 보인다(승하차 처리는 동승자만, M-12).
class _RecordingDriveModeRepository implements DriveModeRepository {
  int startCalls = 0;
  final arrivedStopIds = <String>[];

  @override
  Future<StartRunResult> startRun(String runId) async {
    startCalls++;
    return StartRunResult(
      runStatus: RunStatus.moving,
      startedAt: DateTime(2026, 9, 30, 8),
    );
  }

  @override
  Future<ArriveStopResult> arriveStop({
    required String runId,
    required String stopId,
  }) async {
    arrivedStopIds.add(stopId);
    // 이 시험은 요청이 나갔는지만 본다 — 종료 화면 이동을 피하려고 실패로 끝낸다.
    // Failure 는 Exception/Error 를 상속하지 않는다(다른 시험의 같은 패턴).
    // ignore: only_throw_errors
    throw const NetworkFailure();
  }
}

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

class _FixedClock implements Clock {
  const _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

RosterStop _stop(
  int seq, {
  bool arrived = false,
  StopChange? change,
  List<String> students = const [],
}) => RosterStop(
  stopId: 's$seq',
  seq: seq,
  name: '$seq번 승하차지',
  change: change,
  arrivedAt: arrived ? DateTime(2026, 9, 30, 8, 5) : null,
  students: [
    for (final name in students)
      RosterStudent(
        riderId: 'r-$name',
        studentId: 'st-$name',
        name: name,
        photoUrl: null,
        guardianPhone: null,
        canGoAlone: true,
        status: RiderStatus.waiting,
      ),
  ],
);

RosterResponse _roster(List<RosterStop> stops) => RosterResponse(
  runId: 'run-1',
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  counts: const RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
  stops: stops,
);

void main() {
  // fixture 의 출발 시각(08:00) 안쪽 — 운행 시작 창(±10분)에 든다.
  final now = DateTime(2026, 9, 30, 8, 2);

  Future<_RecordingDriveModeRepository> pumpDrive(
    WidgetTester tester, {
    required RunStatus status,
    required List<RosterStop> stops,
  }) async {
    final repository = _RecordingDriveModeRepository();
    final overrides = <Override>[
      clockProvider.overrideWithValue(_FixedClock(now)),
      tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
      positionSourceProvider.overrideWithValue(_NoSample()),
      routeProvider.overrideWith((ref) async => const RouteResponse(stops: [])),
      selectedRunIdProvider.overrideWith((ref) => 'run-1'),
      currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
      todayRunsProvider.overrideWith(
        (ref) async => [managerRunFixture(status: status)],
      ),
      driveModeRosterProvider.overrideWith((ref) async => _roster(stops)),
      driveModeRepositoryProvider.overrideWithValue(repository),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(home: DriveModeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    return repository;
  }

  group('M6 확인 창', () {
    testWidgets('운행 시작 — 취소하면 요청이 나가지 않고, 확인해야 나간다', (tester) async {
      final repository = await pumpDrive(
        tester,
        status: RunStatus.confirmed,
        stops: [_stop(1)],
      );

      await tester.tap(find.text('운행 시작'));
      await tester.pumpAndSettle();
      expect(find.text('운행을 시작할까요?'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(repository.startCalls, 0);

      await tester.tap(find.text('운행 시작'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('시작하기'));
      await tester.pumpAndSettle();
      expect(repository.startCalls, 1);
    });

    testWidgets('마지막 승하차지 도착 — 취소하면 요청이 나가지 않고, 확인해야 나간다', (tester) async {
      final repository = await pumpDrive(
        tester,
        status: RunStatus.moving,
        stops: [_stop(1, arrived: true), _stop(2)],
      );

      await tester.tap(find.text('도착 처리'));
      await tester.pumpAndSettle();
      expect(find.text('마지막 승하차지입니다'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(repository.arrivedStopIds, isEmpty);

      await tester.tap(find.text('도착 처리'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('도착했습니다'));
      await tester.pumpAndSettle();
      expect(repository.arrivedStopIds, ['s2']);
    });

    testWidgets('마지막이 아닌 승하차지 도착은 확인 없이 바로 나간다(운전 중 조작 부담)', (tester) async {
      final repository = await pumpDrive(
        tester,
        status: RunStatus.moving,
        stops: [_stop(1), _stop(2)],
      );

      await tester.tap(find.text('도착 처리'));
      await tester.pumpAndSettle();

      expect(find.text('마지막 승하차지입니다'), findsNothing);
      expect(repository.arrivedStopIds, ['s1']);
    });

    testWidgets('뒤가 전부 미경유면 지금 승하차지가 마지막이다', (tester) async {
      final repository = await pumpDrive(
        tester,
        status: RunStatus.moving,
        stops: [
          _stop(1),
          _stop(2, change: StopChange.skipped),
        ],
      );

      await tester.tap(find.text('도착 처리'));
      await tester.pumpAndSettle();

      expect(find.text('마지막 승하차지입니다'), findsOneWidget);
      expect(repository.arrivedStopIds, isEmpty);
    });
  });

  group('M5 남은 승하차지', () {
    testWidgets('도착한 곳과 미경유는 빼고 남은 곳만 순서대로, 학생 이름과 함께 보인다', (tester) async {
      await pumpDrive(
        tester,
        status: RunStatus.moving,
        stops: [
          _stop(1, arrived: true),
          _stop(2, students: ['김바래', '이다솜']),
          _stop(3, change: StopChange.skipped),
          _stop(4),
        ],
      );

      final list = find.byKey(const Key('remaining-stops'));
      expect(list, findsOneWidget);
      expect(
        find.descendant(of: list, matching: find.text('남은 승하차지 2곳')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: list, matching: find.text('2번 승하차지')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: list, matching: find.text('4번 승하차지')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: list, matching: find.text('1번 승하차지')),
        findsNothing,
      );
      expect(
        find.descendant(of: list, matching: find.text('3번 승하차지')),
        findsNothing,
      );

      await tester.ensureVisible(
        find.descendant(of: list, matching: find.text('2번 승하차지')),
      );
      await tester.tap(
        find.descendant(of: list, matching: find.text('2번 승하차지')),
      );
      await tester.pumpAndSettle();
      expect(find.text('김바래'), findsOneWidget);
      expect(find.text('이다솜'), findsOneWidget);
    });

    testWidgets('조회 전용 — 승하차 처리 버튼이 없다(M-12)', (tester) async {
      await pumpDrive(
        tester,
        status: RunStatus.moving,
        stops: [
          _stop(1, students: ['김바래']),
        ],
      );

      final list = find.byKey(const Key('remaining-stops'));
      await tester.tap(
        find.descendant(of: list, matching: find.text('1번 승하차지')),
      );
      await tester.pumpAndSettle();

      for (final type in [
        TextButton,
        ElevatedButton,
        FilledButton,
        OutlinedButton,
        Switch,
      ]) {
        expect(
          find.descendant(of: list, matching: find.byType(type)),
          findsNothing,
          reason: '$type — 기사는 승하차를 처리하지 못한다',
        );
      }
    });
  });
}
