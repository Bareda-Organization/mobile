import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/core/runs/domain/run_intent_result.dart';
import 'package:parent_app/core/runs/domain/run_repository.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';
import 'package:parent_app/features/home/presentation/widgets/run_card.dart';

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

/// 첫 조회는 회차 하나를 주고 그 뒤는 실패한다 — 갱신이 실패해도 카드가 남는지 본다.
class _FailingAfterFirstRuns extends _CountingRuns {
  @override
  Future<List<StudentRun>> getRuns(String studentId, {DateTime? date}) async {
    calls++;
    // Failure 는 Exception/Error 를 상속하지 않는다(다른 시험의 같은 패턴).
    // ignore: only_throw_errors
    if (calls > 1) throw const NetworkFailure();
    return [
      StudentRun(
        runId: 'run-1',
        direction: RunDirection.toAcademy,
        busNo: '1호차',
        departTime: DateTime(2026, 9, 12, 8),
        runStatus: RunStatus.idle,
        confirmed: false,
        riding: true,
        riderStatus: RiderStatus.waiting,
        stop: const RunStop(stopId: 'stop-1', name: '정문'),
        changeQuotaLeft: 1,
      ),
    ];
  }
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

  testWidgets('화면을 열어 둔 채 90초가 지나면 회차를 다시 받고, 30초에는 받지 않는다', (tester) async {
    await pumpHome(tester);

    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(runs.calls, 1);

    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    expect(runs.calls, 2);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('앱이 백그라운드인 동안에는 받지 않는다', (tester) async {
    await pumpHome(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 300));

    expect(runs.calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('다른 화면이 홈 위에 있는 동안에는 받지 않는다', (tester) async {
    runs = _CountingRuns();
    final router = GoRouter(
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/live-map',
          builder: (_, _) => const Scaffold(body: Text('지도')),
        ),
      ],
      initialLocation: '/home',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myStudentIdProvider.overrideWith((ref) async => 's-1'),
          runRepositoryProvider.overrideWithValue(runs),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(runs.calls, 1);

    unawaited(router.push('/live-map'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 300));
    expect(runs.calls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // R46 A — 주기 갱신이 실패해도 마지막으로 받은 회차 카드가 남고 오류는 따로 알린다.
  testWidgets('R46 갱신이 실패해도 마지막 회차 카드가 남고 오류 띠를 함께 보인다', (tester) async {
    runs = _FailingAfterFirstRuns();
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          myStudentIdProvider.overrideWith((ref) async => 's-1'),
          runRepositoryProvider.overrideWithValue(runs),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RunCard), findsOneWidget);

    await tester.pump(const Duration(seconds: 91));
    await tester.pumpAndSettle();

    expect(runs.calls, 2);
    expect(find.byType(RunCard), findsOneWidget);
    expect(find.textContaining('이전 정보입니다'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
