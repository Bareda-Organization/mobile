import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/change_requests/domain/change_request_repository.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/runs/presentation/run_providers.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_entry.dart';
import 'package:parent_app/features/schedule/presentation/schedule_providers.dart';
import 'package:parent_app/features/schedule/presentation/schedule_screen.dart';

/// R32 P5 — 자녀를 바꿔도 주소 입력칸·고른 회차가 이전 자녀 값으로 남으면, 다른 아이의 이름으로
/// 저장·신청된다. 두 자녀의 데이터가 이미 캐시에 있는 경우(화면이 로딩을 거치지 않고 곧장
/// 바뀌는 경우)가 재현 조건이다.
class _RecordingChangeRequestRepository implements ChangeRequestRepository {
  final calls = <(String, String)>[];

  @override
  Future<ChangeRequestCreateResult> createChangeRequest(
    String studentId, {
    required ChangeRequestType type,
    required String runId,
    String? newAddress,
    String? reason,
  }) async {
    calls.add((studentId, runId));
    return const ChangeRequestCreateResult(
      changeRequestId: 'c-1',
      status: ChangeRequestStatus.approved,
      result: 'applied',
    );
  }

  @override
  Future<ChangeRequestPage> getChangeRequests(String studentId) async =>
      const ChangeRequestPage(items: [], pendingCount: 0);
}

StudentRun _run(String runId) => StudentRun(
  runId: runId,
  direction: RunDirection.toAcademy,
  busNo: '1호차',
  departTime: DateTime(2026, 9, 12, 8),
  runStatus: RunStatus.idle,
  confirmed: false,
  riding: true,
  riderStatus: RiderStatus.waiting,
  stop: const RunStop(stopId: 'stop-1', name: '정문'),
  changeQuotaLeft: 1,
);

WeeklyAddressEntry _entry(String address) => WeeklyAddressEntry(
  weekday: Weekday.mon,
  direction: RunDirection.toAcademy,
  address: address,
);

Future<(ProviderContainer, _RecordingChangeRequestRepository)> _pump(
  WidgetTester tester,
) async {
  // 폼이 길어 기본 화면(800x600)에서는 ListView 가 아래쪽 위젯을 만들지 않는다.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = _RecordingChangeRequestRepository();
  final container = ProviderContainer(
    overrides: [
      currentUserRoleProvider.overrideWith((ref) => UserRole.parent),
      myStudentsProvider.overrideWith(
        (ref) async => [
          Student(studentId: 's-1', name: '첫째', linkedAt: DateTime(2026, 9)),
          Student(studentId: 's-2', name: '둘째', linkedAt: DateTime(2026, 9)),
        ],
      ),
      weeklyAddressProvider.overrideWith(
        (ref, id) async => [_entry(id == 's-1' ? '첫째 집' : '둘째 집')],
      ),
      runsForStudentProvider.overrideWith(
        (ref, id) async => [_run(id == 's-1' ? 'run-of-s1' : 'run-of-s2')],
      ),
      changeRequestRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  // 두 자녀 모두 미리 불러 둔다 — 자녀를 바꿀 때 로딩을 거치지 않는 조건.
  await container.read(myStudentsProvider.future);
  for (final id in ['s-1', 's-2']) {
    await container.read(weeklyAddressProvider(id).future);
    await container.read(runsForStudentProvider(id).future);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ScheduleScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return (container, repository);
}

void main() {
  testWidgets('P5 자녀를 바꾸면 주소 입력칸이 새 자녀의 주소로 바뀐다', (tester) async {
    final (container, _) = await _pump(tester);
    await tester.enterText(
      find.widgetWithText(TextField, '첫째 집'),
      '첫째 집 고치는 중',
    );

    container.read(selectedStudentIdProvider.notifier).state = 's-2';
    await tester.pumpAndSettle();

    expect(find.text('둘째 집'), findsOneWidget);
    expect(find.text('첫째 집 고치는 중'), findsNothing);
  });

  testWidgets('P5 자녀를 바꾸면 고른 회차가 비워져 다른 자녀의 회차로 신청되지 않는다', (tester) async {
    final (container, repository) = await _pump(tester);
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('등원 · 1호차').last);
    await tester.pumpAndSettle();

    container.read(selectedStudentIdProvider.notifier).state = 's-2';
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BaraedaButton, '변경 신청하기'));
    await tester.pumpAndSettle();

    expect(repository.calls, isEmpty);
  });
}
