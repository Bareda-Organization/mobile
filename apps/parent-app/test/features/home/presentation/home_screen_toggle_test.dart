import 'package:baraeda_ui/baraeda_ui.dart';
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
import 'package:parent_app/features/home/domain/notification_item.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';

/// 서버 대역 — ② 구간에서 끄면 접수만 하고 `riding` 은 그대로 둔다(API_SPEC §3.6·§3.9).
class _ServerRuns implements RunRepository {
  _ServerRuns(this.onIntent);

  final void Function() onIntent;
  int getCalls = 0;

  @override
  Future<List<StudentRun>> getRuns(String studentId, {DateTime? date}) async {
    getCalls++;
    // 두 번째 조회부터 응답이 늦다 — 다시 받는 동안 화면이 어떻게 그려지는지 본다.
    if (getCalls > 1) await Future<void>.delayed(const Duration(seconds: 1));
    return [_run];
  }

  @override
  Future<RunIntentResult> updateIntent(
    String studentId,
    String runId, {
    required bool riding,
  }) async {
    onIntent();
    return const RunIntentResult(
      result: RunIntentApplyResult.pendingApproval,
      riding: true,
      riderStatus: RiderStatus.waiting,
      changeQuotaLeft: 0,
    );
  }
}

class _ServerChangeRequests implements ChangeRequestRepository {
  int pending = 0;

  @override
  Future<ChangeRequestPage> getChangeRequests(String studentId) async =>
      ChangeRequestPage(items: const [], pendingCount: pending);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final _run = StudentRun(
  runId: 'run-1',
  direction: RunDirection.toAcademy,
  busNo: '1호차',
  departTime: DateTime(2026, 9, 12, 8),
  runStatus: RunStatus.confirmed,
  confirmed: true,
  riding: true,
  riderStatus: RiderStatus.waiting,
  stop: const RunStop(stopId: 'stop-1', name: '정문'),
  changeQuotaLeft: 1,
);

/// F05-02 — 홈에서 ② 구간 탑승을 끄면 접수 안내가 남고 "처리 대기" 배지가 1건으로 바뀌어야 한다.
void main() {
  testWidgets('② 구간 끄기 접수 뒤에도 승인 대기 안내가 남고 처리 대기 배지가 갱신된다', (tester) async {
    final changes = _ServerChangeRequests();
    final runs = _ServerRuns(() => changes.pending = 1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
          notificationsProvider.overrideWith(
            (ref) async => const NotificationPage(
              items: [],
              page: 0,
              size: 20,
              totalCount: 0,
              hasNext: false,
              unreadCount: 0,
            ),
          ),
          runRepositoryProvider.overrideWithValue(runs),
          changeRequestRepositoryProvider.overrideWithValue(changes),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('처리 대기'), findsNothing);

    await tester.tap(find.byType(BaraedaSwitch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('탑승 끄기'));
    await tester.pumpAndSettle();

    // 회차 목록을 다시 받는 동안(응답 1초 지연)과 다 받은 뒤 모두 안내가 남는다.
    expect(find.textContaining('학원 관리자 승인 대기 중입니다'), findsOneWidget);
    expect(find.text('처리 대기 · 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.textContaining('학원 관리자 승인 대기 중입니다'), findsOneWidget);
    expect(find.text('처리 대기 · 1'), findsOneWidget);
  });
}
