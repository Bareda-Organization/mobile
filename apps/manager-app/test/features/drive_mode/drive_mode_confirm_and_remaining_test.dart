import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
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
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';
import 'package:manager_app/features/run_end/presentation/run_end_screen.dart';

import '../../support/manager_run_fixture.dart';

/// R32 M5·M6 — 기사 운행 화면. ① 운행 시작 · 마지막 승하차지 도착(= 운행 종료)은 확인 창을 거치고
/// 취소하면 요청이 나가지 않는다 ② 남은 승하차지를 조회 전용으로 보인다(승하차 처리는 동승자만, M-12).
class _RecordingDriveModeRepository implements DriveModeRepository {
  int startCalls = 0;
  final arrivedStopIds = <String>[];

  /// 참이면 연결이 없는 상황 — 도착 처리가 큐에 저장되고 [Queued] 로 끝난다(859).
  bool offline = false;

  /// [offline] 일 때 큐에 저장된 도착 처리 — 화면의 대기 목록(`pendingRequestsProvider`)이 읽는다.
  final queuedRequests = <PendingRequestSummary>[];

  @override
  Future<StartRunResult> startRun(String runId) async {
    startCalls++;
    return StartRunResult(
      runStatus: RunStatus.moving,
      startedAt: DateTime(2026, 9, 30, 8),
    );
  }

  @override
  Future<SendOutcome<ArriveStopResult>> arriveStop({
    required String runId,
    required String stopId,
  }) async {
    arrivedStopIds.add(stopId);
    if (offline) {
      queuedRequests.add(
        PendingRequestSummary(
          id: queuedRequests.length + 1,
          endpoint: '/runs/$runId/stops/$stopId/arrive',
          method: 'POST',
          payload: '{}',
          createdAt: DateTime(2026, 9, 30, 8, 1),
        ),
      );
      return const Queued();
    }
    // 이 시험은 요청이 나갔는지만 본다 — 종료 화면 이동을 피하려고 실패로 끝낸다.
    // Failure 는 Exception/Error 를 상속하지 않는다(다른 시험의 같은 패턴).
    // ignore: only_throw_errors
    throw const NetworkFailure();
  }
}

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

class _FixedClock implements Clock {
  const new(this._now);

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

RosterResponse _roster(
  List<RosterStop> stops, {
  RunDirection direction = RunDirection.toAcademy,
  DateTime? cachedAt,
}) => RosterResponse(
  runId: 'run-1',
  busNo: '3호차',
  direction: direction,
  counts: const RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
  stops: stops,
  cachedAt: cachedAt,
);

int rosterLoads = 0;

void main() {
  // fixture 의 출발 시각(08:00) 안쪽 — 운행 시작 창(±10분)에 든다.
  final now = DateTime(2026, 9, 30, 8, 2);

  Future<_RecordingDriveModeRepository> pumpDrive(
    WidgetTester tester, {
    required RunStatus status,
    required List<RosterStop> stops,
    RunDirection direction = RunDirection.toAcademy,
    bool offline = false,
    DateTime? cachedAt,
  }) async {
    rosterLoads = 0;
    final repository = _RecordingDriveModeRepository()..offline = offline;
    final overrides = <Override>[
      clockProvider.overrideWithValue(_FixedClock(now)),
      tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
      positionSourceProvider.overrideWithValue(_NoSample()),
      routeProvider.overrideWith((ref) async => const RouteResponse(stops: [])),
      selectedRunIdProvider.overrideWith((ref) => 'run-1'),
      currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
      todayRunsProvider.overrideWith(
        (ref) async => [
          managerRunFixture(status: status, direction: direction),
        ],
      ),
      driveModeRepositoryProvider.overrideWithValue(repository),
      pendingRequestsProvider.overrideWith(
        (ref) async => List.of(repository.queuedRequests),
      ),
      driveModeRosterProvider.overrideWith((ref) async {
        rosterLoads++;
        return _roster(stops, direction: direction, cachedAt: cachedAt);
      }),
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
    // 운행 시작 확인 창은 운행 준비 화면으로 옮겼다 — `run_ready_screen_test.dart` 가 문다.

    testWidgets('마지막 승하차지 도착 — 취소하면 요청이 나가지 않고, 확인해야 나간다', (tester) async {
      final repository = await pumpDrive(
        tester,
        status: RunStatus.moving,
        stops: [_stop(1, arrived: true), _stop(2)],
      );

      await tester.tap(find.text('도착 처리'));
      await tester.pumpAndSettle();
      expect(find.text('마지막 승하차지예요'), findsOneWidget);
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      expect(repository.arrivedStopIds, isEmpty);

      await tester.tap(find.text('도착 처리'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('도착했어요 · 운행 종료'));
      await tester.pumpAndSettle();
      expect(repository.arrivedStopIds, ['s2']);
    });

    // L3 — 등원은 도착이 곧 종료·전원 자동 하차, 하원은 도착만 기록되고 남은 학생이 있으면 종료가 보류된다(C-15).
    testWidgets('등원 마지막 승하차지 확인 창은 전원 자동 하차와 위치 중단을 알린다', (tester) async {
      await pumpDrive(
        tester,
        status: RunStatus.moving,
        stops: [_stop(1, arrived: true), _stop(2)],
      );

      await tester.tap(find.text('도착 처리'));
      await tester.pumpAndSettle();

      expect(find.textContaining('전원이 자동으로 하차 처리돼요'), findsOneWidget);
      expect(find.textContaining('보류'), findsNothing);
      expect(find.text('도착했어요 · 운행 종료'), findsOneWidget);
    });

    testWidgets('하원 마지막 승하차지 확인 창은 자동 하차 대신 종료 보류를 알린다', (tester) async {
      final repository = await pumpDrive(
        tester,
        status: RunStatus.moving,
        stops: [_stop(1, arrived: true), _stop(2)],
        direction: RunDirection.fromAcademy,
      );

      await tester.tap(find.text('도착 처리'));
      await tester.pumpAndSettle();

      expect(find.textContaining('자동으로 하차'), findsNothing);
      expect(find.textContaining('위치 보내기가 멈춰요'), findsNothing);
      expect(find.textContaining('종료가 보류'), findsOneWidget);
      expect(find.text('도착했어요 · 운행 종료'), findsNothing);
      await tester.tap(find.text('도착했어요'));
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

      expect(find.text('마지막 승하차지예요'), findsNothing);
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

      expect(find.text('마지막 승하차지예요'), findsOneWidget);
      expect(repository.arrivedStopIds, isEmpty);
    });
  });

  // 859(UF-D-04 · §12.2) — 도착 처리는 연결이 없어도 기기에 저장된다. "저장돼요" 안내가 사실이 되려면 저장된 곳을
  // 처리한 곳으로 보고 다음 곳을 가리켜야 하고(같은 곳을 다시 보내지 않는다), 서버 응답이 필요한 종료 화면으로는
  // 가지 않는다.
  // M-M3 — 기기에 저장해 둔 명단으로 다음 승하차지를 가리키는 동안에도 연결이 돌아오면 서버 명단으로 바뀐다.
  testWidgets('저장해 둔 명단을 보는 동안은 주기마다 서버에서 다시 받아 본다', (tester) async {
    await pumpDrive(
      tester,
      status: RunStatus.moving,
      stops: [_stop(1), _stop(2)],
      cachedAt: DateTime(2026, 9, 30, 7, 50),
    );
    final first = rosterLoads;

    await tester.pump(const Duration(seconds: 16));
    await tester.pump();

    expect(rosterLoads, greaterThan(first));
  });

  group('H4 연결 없는 도착 처리', () {
    testWidgets('저장 안내를 보이고 다음 누름은 다음 승하차지를 보낸다', (tester) async {
      final repository = await pumpDrive(
        tester,
        status: RunStatus.moving,
        stops: [_stop(1), _stop(2), _stop(3)],
        offline: true,
      );

      await tester.tap(find.text('도착 처리'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('도착을 저장했어요 · 연결되면 보내요'), findsOneWidget);
      expect(repository.arrivedStopIds, ['s1']);

      await tester.pump(const Duration(seconds: 6));
      await tester.tap(find.text('도착 처리'));
      await tester.pump();
      await tester.pump();

      expect(repository.arrivedStopIds, ['s1', 's2']);
      await tester.pump(const Duration(seconds: 6));
    });

    // 큐가 비면(연결이 돌아와 저장된 도착이 서버로 나갔다) 명단을 다시 받는다 — 안 그러면 저장된 곳이 "처리한 곳" 에서
    // 빠지는 순간 이미 도착한 곳이 다음 곳으로 되살아난다.
    testWidgets('저장된 도착이 서버로 나가 큐가 비면 명단과 회차를 다시 받는다', (tester) async {
      final repository = await pumpDrive(
        tester,
        status: RunStatus.moving,
        stops: [_stop(1), _stop(2)],
        offline: true,
      );
      await tester.tap(find.text('도착 처리'));
      await tester.pump();
      await tester.pump();
      final loadsWhileQueued = rosterLoads;

      repository.queuedRequests.clear();
      ProviderScope.containerOf(
        tester.element(find.byType(DriveModeScreen)),
      ).invalidate(pendingRequestsProvider);
      await tester.pump();
      await tester.pump();

      expect(rosterLoads, greaterThan(loadsWhileQueued));
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('마지막 승하차지 도착이 저장되면 종료 화면 대신 저장 안내가 남는다', (tester) async {
      final repository = await pumpDrive(
        tester,
        status: RunStatus.moving,
        stops: [_stop(1, arrived: true), _stop(2)],
        offline: true,
      );

      await tester.tap(find.text('도착 처리'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('도착했어요 · 운행 종료'));
      await tester.pump();
      await tester.pump();

      expect(repository.arrivedStopIds, ['s2']);
      expect(find.byType(RunEndScreen), findsNothing);
      expect(find.text('도착 처리를 저장했어요 · 연결되면 서버로 보내요'), findsOneWidget);
      expect(find.text('도착 처리'), findsNothing);
      await tester.pump(const Duration(seconds: 6));
    });
  });

  group('M5 남은 승하차지', () {
    testWidgets('도착한 곳은 빼고 남은 곳을 순서대로, 미경유는 건너뜀 표시와 함께 보인다', (tester) async {
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
      // 남은 곳 수에는 미경유가 들어가지 않는다 — 2곳 + "미경유 1곳은 건너뛰어요".
      expect(
        find.descendant(of: list, matching: find.text('남은 승하차지 2곳')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: list, matching: find.text('미경유 1곳은 건너뛰어요')),
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
        reason: '이미 도착한 곳은 남은 목록에 없다',
      );
      // 미경유는 목록에 남되 정차 안 함으로 표시된다.
      expect(
        find.descendant(of: list, matching: find.text('정차 안 함')),
        findsOneWidget,
      );
      // 다음 도착지 카드에 이름이 크게 나오고 학생 수가 부제로 붙는다.
      expect(find.text('다음 승하차지 · 2번'), findsOneWidget);
      expect(find.text('탑승 예정 2명'), findsOneWidget);
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

      for (final type in [
        TextButton,
        ElevatedButton,
        FilledButton,
        OutlinedButton,
        BaraedaButton,
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
