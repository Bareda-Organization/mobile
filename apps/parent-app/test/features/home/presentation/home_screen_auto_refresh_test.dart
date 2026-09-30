import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/runs/domain/run_intent_result.dart';
import 'package:parent_app/core/runs/domain/run_repository.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';

class _CountingRuns implements RunRepository {
  int calls = 0;

  @override
  Future<List<StudentRun>> getRuns(String studentId, {DateTime? date}) async {
    calls++;
    return const [];
  }

  @override
  Future<RunIntentResult> updateIntent(
    String studentId,
    String runId, {
    required bool riding,
  }) => throw UnimplementedError();
}

/// F05-06 — 푸시 SDK 가 없어 앱 안 갱신이 유일한 통지 수단이다. 당기지 않아도 앱에 돌아오거나 일정 시간이
/// 지나면 회차를 다시 받아야 한다(알림은 `AppShell` 이 받는다 — `app_shell_test.dart`).
void main() {
  late _CountingRuns runs;

  Future<void> pumpHome(WidgetTester tester) async {
    runs = _CountingRuns();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myStudentIdProvider.overrideWith((ref) async => 's-1'),
          runRepositoryProvider.overrideWithValue(runs),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('앱이 백그라운드에서 돌아오면 회차를 다시 받는다', (tester) async {
    await pumpHome(tester);
    expect(runs.calls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(runs.calls, 2);
  });

  testWidgets('화면을 열어 둔 채 30초가 지나면 회차를 다시 받는다', (tester) async {
    await pumpHome(tester);

    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    expect(runs.calls, 2);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
