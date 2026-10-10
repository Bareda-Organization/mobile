import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/me_provider.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/home/presentation/home_screen.dart';

import '../../support/fake_notification_repository.dart';
import '../../support/manager_run_fixture.dart';

/// R52 H1 — 앞 회차(A)가 끝난 뒤에도 선택 회차([selectedRunIdProvider])가 A 에 남아 있으면 홈 큰 카드는 다음 회차(B)로
/// 넘어가는데 운행 준비 · 명단 · 운행 화면은 끝난 A 를 그렸다. 홈 단추는 큰 카드가 가리키는 회차로 선택을 맞춘 뒤 간다.
void main() {
  final now = DateTime(2026, 10, 3, 12, 14);
  final depart = DateTime(2026, 10, 3, 12, 20);

  GoRouter buildRouter() {
    Widget marker(String label) => Consumer(
      builder: (context, ref, _) => Text(
        '$label:${ref.watch(selectedRunIdProvider)}'
        ':${ref.watch(driveModeRunProvider)?.busNo}',
      ),
    );
    return GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const ManagerHomeScreen(),
        ),
        GoRoute(
          path: AppRoutes.runReady,
          builder: (context, state) => marker('RUN_READY'),
        ),
        GoRoute(
          path: AppRoutes.driveMode,
          builder: (context, state) => marker('DRIVE_MODE'),
        ),
        GoRoute(
          path: AppRoutes.roster,
          builder: (context, state) => marker('ROSTER'),
        ),
      ],
    );
  }

  Widget wrap(UserRole role, {required RunStatus nextStatus}) {
    final List<Override> overrides = [
      clockProvider.overrideWithValue(_FixedClock(now)),
      notificationRepositoryProvider.overrideWithValue(
        FakeNotificationRepository(const []),
      ),
      meProvider.overrideWith(
        (ref) async => const MeResponse(
          accountId: '1',
          loginId: 'driverA2',
          name: '박정훈',
          phone: '010-0000-0000',
          role: AccountRole.driver,
          status: AccountStatus.active,
        ),
      ),
      currentUserRoleProvider.overrideWith((ref) => role),
      todayRunsProvider.overrideWith(
        (ref) async => [
          managerRunFixture(
            runId: 'run-A',
            busNo: '1호차',
            status: RunStatus.finished,
            departTime: DateTime(2026, 10, 3, 8),
          ),
          managerRunFixture(
            runId: 'run-B',
            busNo: '2호차',
            status: nextStatus,
            departTime: depart,
          ),
        ],
      ),
      // 방금 끝낸 운행 A 가 아직 선택돼 있다.
      selectedRunIdProvider.overrideWith((ref) => 'run-A'),
    ];
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(routerConfig: buildRouter()),
    );
  }

  testWidgets('A 종료 · B 확정이면 [운행 준비하기] 가 B 의 화면을 연다', (tester) async {
    await tester.pumpWidget(
      wrap(UserRole.driver, nextStatus: RunStatus.confirmed),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('운행 준비하기'));
    await tester.pumpAndSettle();

    expect(find.text('RUN_READY:run-B:2호차'), findsOneWidget);
  });

  testWidgets('A 종료 · B 운행 중이면 [운행 화면으로] 가 B 의 화면을 연다', (tester) async {
    await tester.pumpWidget(
      wrap(UserRole.driver, nextStatus: RunStatus.moving),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('운행 화면으로'));
    await tester.pumpAndSettle();

    expect(find.text('DRIVE_MODE:run-B:2호차'), findsOneWidget);
  });

  testWidgets('A 종료 · B 확정이면 동승자 [명단 열기] 가 B 의 명단을 연다', (tester) async {
    await tester.pumpWidget(
      wrap(UserRole.escort, nextStatus: RunStatus.confirmed),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('명단 열기'));
    await tester.pumpAndSettle();

    expect(find.text('ROSTER:run-B:2호차'), findsOneWidget);
  });
}

class _FixedClock implements Clock {
  const new(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}
