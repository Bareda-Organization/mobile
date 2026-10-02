import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/role_policy.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/change_requests/presentation/change_request_providers.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/core/runs/domain/run_intent_result.dart';
import 'package:parent_app/core/runs/domain/run_repository.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';

/// R34 P1 — 홈의 [오늘 · 내일] 전환. 조회 날짜·토글 요청 대상·학생 조회 전용을 본다.
class _FixedClock implements Clock {
  const new(this._value);

  final DateTime _value;

  @override
  DateTime now() => _value;
}

/// 조회한 날짜와 토글 요청을 기록하고, 날짜별로 다른 회차를 돌려주는 가짜.
class _DatedRunRepository implements RunRepository {
  new({this.tomorrow = const []});

  final List<StudentRun> tomorrow;
  final requestedDates = <DateTime?>[];
  final intents = <(String runId, bool riding)>[];

  @override
  Future<List<StudentRun>> getRuns(String studentId, {DateTime? date}) async {
    requestedDates.add(date);
    return date == null ? [_run('run-today', '1호차')] : tomorrow;
  }

  @override
  Future<RunIntentResult> updateIntent(
    String studentId,
    String runId, {
    required bool riding,
  }) async {
    intents.add((runId, riding));
    return RunIntentResult(
      result: RunIntentApplyResult.applied,
      riding: riding,
      riderStatus: RiderStatus.waiting,
      changeQuotaLeft: 1,
    );
  }
}

StudentRun _run(String runId, String busNo) => StudentRun(
  runId: runId,
  direction: RunDirection.toAcademy,
  busNo: busNo,
  departTime: DateTime(2026, 10, 2, 8),
  runStatus: RunStatus.idle,
  confirmed: false,
  riding: true,
  riderStatus: RiderStatus.waiting,
  stop: const RunStop(stopId: 'stop-1', name: '정문'),
  changeQuotaLeft: 2,
);

void main() {
  // 세계 표준시 9월 30일 16:00 = 한국 시간 10월 1일 01:00 → 한국 시간 내일은 10월 2일.
  final now = DateTime.utc(2026, 9, 30, 16);
  final tomorrowRun = _run('run-tomorrow', '2호차');

  Future<_DatedRunRepository> pumpHome(
    WidgetTester tester, {
    required UserRole role,
    List<StudentRun> tomorrow = const [],
  }) async {
    final runs = _DatedRunRepository(tomorrow: tomorrow);
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(_FixedClock(now)),
          runRepositoryProvider.overrideWithValue(runs),
          roleCapabilitiesProvider.overrideWithValue(RoleCapabilities.of(role)),
          myStudentIdProvider.overrideWith((ref) async => 's-1'),
          myStudentsProvider.overrideWith(
            (ref) async => [
              Student(
                studentId: 's-1',
                name: '첫째',
                linkedAt: DateTime(2026, 9),
              ),
            ],
          ),
          changeRequestsProvider.overrideWith(
            (ref, studentId) async =>
                const ChangeRequestPage(items: [], pendingCount: 0),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return runs;
  }

  testWidgets('내일을 고르면 한국 시간 기준 내일 날짜로 회차를 조회하고 그 회차를 보여준다', (tester) async {
    final runs = await pumpHome(
      tester,
      role: UserRole.parent,
      tomorrow: [tomorrowRun],
    );
    expect(find.textContaining('1호차'), findsOneWidget);

    await tester.tap(find.text('내일'));
    await tester.pumpAndSettle();

    final requested = runs.requestedDates.last!;
    expect((requested.year, requested.month, requested.day), (2026, 10, 2));
    expect(find.textContaining('2호차'), findsOneWidget);
    expect(find.textContaining('1호차'), findsNothing);
  });

  testWidgets('내일 회차의 탑승 스위치는 내일 회차 id 로 요청을 보낸다', (tester) async {
    final runs = await pumpHome(
      tester,
      role: UserRole.parent,
      tomorrow: [tomorrowRun],
    );
    await tester.tap(find.text('내일'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BaraedaSwitch));
    await tester.pumpAndSettle();
    expect(find.text('내일 탑승을 취소할까요?'), findsOneWidget);
    await tester.tap(find.text('탑승 취소'));
    await tester.pumpAndSettle();

    expect(runs.intents, [('run-tomorrow', false)]);
  });

  testWidgets('내일 회차를 바꾼 뒤에는 내일 목록을 다시 받는다', (tester) async {
    final runs = await pumpHome(
      tester,
      role: UserRole.parent,
      tomorrow: [tomorrowRun],
    );
    await tester.tap(find.text('내일'));
    await tester.pumpAndSettle();
    final before = runs.requestedDates.where((d) => d != null).length;

    await tester.tap(find.byType(BaraedaSwitch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('탑승 취소'));
    await tester.pumpAndSettle();

    expect(runs.requestedDates.where((d) => d != null).length, before + 1);
  });

  testWidgets('내일 회차가 없으면 내일 안내를 보여준다', (tester) async {
    await pumpHome(tester, role: UserRole.parent);

    await tester.tap(find.text('내일'));
    await tester.pumpAndSettle();

    expect(find.text('내일 예정된 회차가 없습니다'), findsOneWidget);
  });

  testWidgets('학생은 내일 회차를 볼 수 있지만 탑승 스위치는 없다', (tester) async {
    await pumpHome(tester, role: UserRole.student, tomorrow: [tomorrowRun]);

    await tester.tap(find.text('내일'));
    await tester.pumpAndSettle();

    expect(find.textContaining('2호차'), findsOneWidget);
    expect(find.byType(BaraedaSwitch), findsNothing);
  });
}
