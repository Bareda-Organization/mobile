import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/roster/data/models/ack_changes_result.dart';
import 'package:manager_app/features/roster/data/models/boarding_update_request.dart';
import 'package:manager_app/features/roster/data/models/no_show_contact_request.dart';
import 'package:manager_app/features/roster/data/models/revert_result.dart';
import 'package:manager_app/features/roster/data/models/rider_update_result.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/domain/roster_repository.dart';
import 'package:manager_app/features/roster/presentation/roster_screen.dart';

/// 테스트 전용 대역 — §4.11 ack-changes 호출 여부·인자만 기록하고, §4.7
/// 되돌리기(`revertRiderStatus`)도 성공·실패를 주입할 수 있다. 나머지 쓰기
/// 2종(승하차 갱신·미탑승 연락 기록)은 이 파일의 시험 대상이 아니라 호출되면
/// 실패하도록 둔다.
class _FakeRosterRepository implements RosterRepository {
  _FakeRosterRepository({
    required this.roster,
    this.ackResult,
    this.ackFailure,
    this.revertFailure,
  });

  final RosterResponse roster;
  final AckChangesResult? ackResult;
  final Failure? ackFailure;
  final Failure? revertFailure;
  String? lastAckRunId;
  List<String>? lastAckChangeIds;

  @override
  Future<RosterResponse> fetchRoster(String runId) async => roster;

  @override
  Future<AckChangesResult> ackChanges({
    required String runId,
    List<String>? changeIds,
  }) async {
    lastAckRunId = runId;
    lastAckChangeIds = changeIds;
    // Failure 는 의도적으로 Exception/Error 를 상속하지 않는다
    // (baraeda_core/error/failure.dart 참고) — delay_screen_test.dart 와
    // 같은 패턴.
    // ignore: only_throw_errors
    if (ackFailure != null) throw ackFailure!;
    return ackResult!;
  }

  @override
  Future<RiderUpdateResult> updateRiderStatus({
    required String runId,
    required String riderId,
    required BoardingUpdateRequest request,
  }) => throw UnimplementedError('이 파일의 시험 대상이 아니다');

  @override
  Future<RevertResult> revertRiderStatus({
    required String runId,
    required String riderId,
    String? reason,
  }) async {
    // Failure 는 의도적으로 Exception/Error 를 상속하지 않는다(위 ackChanges
    // 주석과 같은 이유).
    // ignore: only_throw_errors
    if (revertFailure != null) throw revertFailure!;
    return RevertResult(
      status: RiderStatus.waiting,
      revertedAt: DateTime(2026, 9, 12, 9),
    );
  }

  @override
  Future<void> recordNoShowContact({
    required String runId,
    required String riderId,
    required NoShowContactRequest request,
  }) => throw UnimplementedError('이 파일의 시험 대상이 아니다');
}

Widget _wrap(Widget child, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

/// §4.2 응답 — 정류장·탑승자별 `change` 는 초록 하이라이트·빨강 취소선
/// 표시(UF-D-02)에만 쓰인다. 배너 노출 근거는 더 이상 이 값이 아니라
/// [_managerRun] 의 `ackRequired`(§4.1) 다.
RosterResponse _roster({
  RiderChange? studentChange,
  StopChange? stopChange,
  RiderStatus studentStatus = RiderStatus.waiting,
}) {
  return RosterResponse(
    runId: 'run-1',
    busNo: '3호차',
    direction: RunDirection.toAcademy,
    counts: const RosterCounts(boarded: 0, waiting: 1, noShow: 0, absentN: 0),
    stops: [
      RosterStop(
        stopId: 'stop-1',
        seq: 1,
        name: 'A정류장',
        change: stopChange,
        students: [
          RosterStudent(
            riderId: 'r1',
            studentId: 's1',
            name: '김바래',
            photoUrl: 'https://example/1.jpg',
            guardianPhone: '010-2XXX-8814',
            canGoAlone: false,
            status: studentStatus,
            change: studentChange,
          ),
        ],
      ),
    ],
  );
}

/// §4.1 `GET /manager/runs` 항목 — `ackRequired` 가 §4.11 배너 노출의
/// 근거값(RUN-07).
ManagerRun _managerRun({required bool ackRequired}) {
  final now = DateTime(2026, 9, 12, 8);
  return ManagerRun(
    runId: 'run-1',
    busNo: '3호차',
    direction: RunDirection.toAcademy,
    departTime: now,
    origin: '기점',
    destination: '학원',
    estDurationMin: 30,
    runStatus: RunStatus.confirmed,
    confirmed: true,
    startWindowFrom: now.subtract(const Duration(minutes: 10)),
    startWindowTo: now.add(const Duration(minutes: 10)),
    addedCount: 0,
    removedCount: 0,
    ackRequired: ackRequired,
  );
}

void main() {
  const runId = 'run-1';

  List<Override> overridesFor({
    required RosterResponse roster,
    required bool ackRequired,
    AckChangesResult? ackResult,
    Failure? ackFailure,
  }) {
    final fakeRepo = _FakeRosterRepository(
      roster: roster,
      ackResult: ackResult,
      ackFailure: ackFailure,
    );
    return [
      selectedRunIdProvider.overrideWith((ref) => runId),
      rosterRepositoryProvider.overrideWithValue(fakeRepo),
      todayRunsProvider.overrideWith(
        (ref) async => [_managerRun(ackRequired: ackRequired)],
      ),
    ];
  }

  testWidgets('ack_required 가 false 면 변경 확인 배너를 보여주지 않는다', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RosterScreen(),
        overridesFor(roster: _roster(), ackRequired: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('변경 목록 확인'), findsNothing);
  });

  testWidgets('ack_required 가 true 면 변경 확인 배너·버튼을 보여준다', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RosterScreen(),
        overridesFor(
          roster: _roster(studentChange: RiderChange.added),
          ackRequired: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('승하차지·명단이 변경됐습니다'), findsOneWidget);
    expect(find.text('변경 목록 확인'), findsOneWidget);
  });

  testWidgets('변경 목록 확인을 누르면 ack-changes 를 호출하고 배너를 닫는다', (tester) async {
    final overrides = overridesFor(
      roster: _roster(stopChange: StopChange.added),
      ackRequired: true,
      ackResult: AckChangesResult(ackedAt: DateTime(2026, 9, 12, 9)),
    );

    await tester.pumpWidget(_wrap(const RosterScreen(), overrides));
    await tester.pumpAndSettle();

    await tester.tap(find.text('변경 목록 확인'));
    await tester.pumpAndSettle();

    expect(find.text('변경 목록 확인'), findsNothing);
  });

  testWidgets('변경 목록 확인 호출 시 change_ids 를 전달하지 않는다(전건 확인)', (tester) async {
    final fakeRepo = _FakeRosterRepository(
      roster: _roster(stopChange: StopChange.added),
      ackResult: AckChangesResult(ackedAt: DateTime(2026, 9, 12, 9)),
    );

    await tester.pumpWidget(
      _wrap(const RosterScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        rosterRepositoryProvider.overrideWithValue(fakeRepo),
        todayRunsProvider.overrideWith(
          (ref) async => [_managerRun(ackRequired: true)],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('변경 목록 확인'));
    await tester.pumpAndSettle();

    expect(fakeRepo.lastAckRunId, runId);
    expect(fakeRepo.lastAckChangeIds, isNull);
  });

  testWidgets('ack-changes 가 실패하면 실패 사유를 보여주고 배너는 남는다', (tester) async {
    final fakeRepo = _FakeRosterRepository(
      roster: _roster(stopChange: StopChange.added),
      ackFailure: const ApiFailure(
        statusCode: 409,
        code: 'RUN_NOT_CONFIRMED',
        message: '확정 전',
      ),
    );

    await tester.pumpWidget(
      _wrap(const RosterScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        rosterRepositoryProvider.overrideWithValue(fakeRepo),
        todayRunsProvider.overrideWith(
          (ref) async => [_managerRun(ackRequired: true)],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('변경 목록 확인'));
    await tester.pumpAndSettle();

    expect(find.text('아직 확정되지 않은 운행입니다'), findsOneWidget);
    expect(find.text('변경 목록 확인'), findsOneWidget);
  });

  testWidgets('되돌리기(§4.7)가 실패하면 실패 사유를 보여준다', (tester) async {
    // 되돌리기 버튼은 canDecide(동승자 전용)일 때만 그려지고, waiting 상태의
    // 학생에는 아예 노출되지 않는다(roster_screen.dart `_StudentActions`) —
    // 그래서 이 시험만 role 을 동승자로 override 하고 학생 상태를 boarded
    // 로 바꿔 버튼을 실제로 그리게 한다.
    final fakeRepo = _FakeRosterRepository(
      roster: _roster(studentStatus: RiderStatus.boarded),
      revertFailure: const ApiFailure(
        statusCode: 409,
        code: 'REVERT_WINDOW_EXPIRED',
        message: '되돌리기 가능 시간이 지났습니다',
      ),
    );

    await tester.pumpWidget(
      _wrap(const RosterScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        rosterRepositoryProvider.overrideWithValue(fakeRepo),
        currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
        todayRunsProvider.overrideWith(
          (ref) async => [_managerRun(ackRequired: false)],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('되돌리기'));
    await tester.pumpAndSettle();

    expect(find.text('되돌리기 가능 시간이 지났습니다'), findsOneWidget);
  });
}
