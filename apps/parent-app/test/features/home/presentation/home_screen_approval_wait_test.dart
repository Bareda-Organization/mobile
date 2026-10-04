import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/role_policy.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/change_requests/domain/change_request_repository.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/core/runs/domain/run_intent_result.dart';
import 'package:parent_app/core/runs/domain/run_repository.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';
import '../../../support/no_bus_position.dart';

/// A #15(`FEATURE_SPEC P-03`) — ②구간 신청이 승인을 기다리는 회차 카드에 "출발까지" 남은 시간을 붙인다.
/// 신청 이력(§3.9)의 `pending` 이 기준이라 앱을 다시 켜도 남는다(토글 직후 한 번 뜨는 안내와 별개).
class _Runs implements RunRepository {
  @override
  Future<List<StudentRun>> getRuns(String studentId, {DateTime? date}) async =>
      [_run('run-1', '1호차'), _run('run-2', '2호차')];

  @override
  Future<RunIntentResult> updateIntent(
    String studentId,
    String runId, {
    required bool riding,
  }) => throw UnimplementedError();
}

class _Changes implements ChangeRequestRepository {
  @override
  Future<ChangeRequestPage> getChangeRequests(String studentId) async =>
      const ChangeRequestPage(
        pendingCount: 1,
        items: [
          ChangeRequest(
            changeRequestId: 'c-1',
            type: ChangeRequestType.cancel,
            status: ChangeRequestStatus.pending,
            runId: 'run-1',
          ),
          // 처리된 신청은 기다리는 중이 아니다.
          ChangeRequest(
            changeRequestId: 'c-0',
            type: ChangeRequestType.cancel,
            status: ChangeRequestStatus.approved,
            runId: 'run-2',
          ),
        ],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Clock implements Clock {
  @override
  DateTime now() => DateTime(2026, 9, 12, 7, 30);
}

StudentRun _run(String id, String bus) => StudentRun(
  runId: id,
  direction: RunDirection.toAcademy,
  busNo: bus,
  departTime: DateTime(2026, 9, 12, 8),
  runStatus: RunStatus.confirmed,
  confirmed: true,
  riding: true,
  riderStatus: RiderStatus.waiting,
  stop: const RunStop(stopId: 'stop-1', name: '정문'),
  changeQuotaLeft: 0,
);

void main() {
  testWidgets('승인 대기 신청이 걸린 회차 카드에만 출발까지 남은 시간이 붙는다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noBusPositionOverride,
          roleCapabilitiesProvider.overrideWithValue(
            RoleCapabilities.of(UserRole.parent),
          ),
          myStudentsProvider.overrideWith(
            (ref) async => [
              Student(
                studentId: 's-1',
                name: '첫째',
                linkedAt: DateTime(2026, 9),
              ),
            ],
          ),
          runRepositoryProvider.overrideWithValue(_Runs()),
          changeRequestRepositoryProvider.overrideWithValue(_Changes()),
          clockProvider.overrideWithValue(_Clock()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('승인 대기 · 출발까지 30분'), findsOneWidget);
  });
}
