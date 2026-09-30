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
import 'package:parent_app/core/students/data/selected_student_storage.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';

/// R46 B2 #13 — 앱을 다시 켜도 마지막으로 본 자녀의 회차가 홈에 뜬다.
class _MemoryStorage extends SelectedStudentStorage {
  _MemoryStorage(this.saved);

  String? saved;

  @override
  Future<String?> read() async => saved;

  @override
  Future<void> save(String studentId) async => saved = studentId;
}

class _Runs implements RunRepository {
  @override
  Future<List<StudentRun>> getRuns(String studentId, {DateTime? date}) async =>
      [
        StudentRun(
          runId: 'run-$studentId',
          direction: RunDirection.toAcademy,
          // 자녀마다 다른 호차 — 화면에 어느 자녀의 회차가 떴는지 가른다.
          busNo: studentId == 's-2' ? '2호차' : '1호차',
          departTime: DateTime(2026, 9, 12, 8),
          runStatus: RunStatus.idle,
          confirmed: false,
          riding: true,
          riderStatus: RiderStatus.waiting,
          stop: const RunStop(stopId: 'stop-1', name: '정문'),
          changeQuotaLeft: 1,
        ),
      ];

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
      const ChangeRequestPage(items: [], pendingCount: 0);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<ProviderContainer> _pumpHome(
  WidgetTester tester,
  _MemoryStorage storage,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        roleCapabilitiesProvider.overrideWithValue(
          RoleCapabilities.of(UserRole.parent),
        ),
        myStudentsProvider.overrideWith(
          (ref) async => [
            Student(studentId: 's-1', name: '첫째', linkedAt: DateTime(2026)),
            Student(studentId: 's-2', name: '둘째', linkedAt: DateTime(2026)),
          ],
        ),
        runRepositoryProvider.overrideWithValue(_Runs()),
        changeRequestRepositoryProvider.overrideWithValue(_Changes()),
        selectedStudentStorageProvider.overrideWithValue(storage),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(HomeScreen)),
    listen: false,
  );
}

void main() {
  testWidgets('기억해 둔 자녀가 있으면 첫 자녀가 아니라 그 자녀의 회차가 뜬다', (tester) async {
    await _pumpHome(tester, _MemoryStorage('s-2'));

    expect(find.textContaining('2호차'), findsOneWidget);
    expect(find.textContaining('1호차'), findsNothing);
  });

  testWidgets('기억한 것이 없으면 첫 자녀가 뜨고, 자녀를 바꾸면 그 선택을 기억한다', (tester) async {
    final storage = _MemoryStorage(null);
    await _pumpHome(tester, storage);
    expect(find.textContaining('1호차'), findsOneWidget);

    await tester.tap(find.text('둘째'));
    await tester.pumpAndSettle();

    expect(find.textContaining('2호차'), findsOneWidget);
    expect(storage.saved, 's-2');
  });
}
