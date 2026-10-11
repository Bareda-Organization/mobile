import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/app.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/me_provider.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/manager_run_channel.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/home/presentation/home_screen.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';

import '../support/fake_notification_repository.dart';
import '../support/fake_token_storage.dart';
import '../support/manager_run_fixture.dart';

/// R53 t4 A1 — 오늘 회차 목록 30초 새로 고침 · 앱 복귀 처리는 홈 탭이 아니라 쉘이 맡는다. 동승자의 첫 화면은 명단
/// 탭이고 탭은 처음 갈 때 만들어지므로, 홈에 두면 명단 탭에 머무는 동안 확정(서버 배치)이 목록에 닿지 않았다.
void main() {
  late int fetches;
  late FakeNotificationRepository notifications;

  Future<ProviderContainer> pump(WidgetTester tester, UserRole role) async {
    fetches = 0;
    notifications = FakeNotificationRepository(const []);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          currentUserRoleProvider.overrideWith((ref) => role),
          currentAccountStatusProvider.overrideWith(
            (ref) => AccountStatus.active,
          ),
          meProvider.overrideWith((ref) async => throw StateError('내 정보 미사용')),
          todayRunsProvider.overrideWith((ref) async {
            fetches++;
            return [
              // 첫 조회는 확정 전, 그 뒤는 확정 — 서버 배치가 확정 시각에 상태를 바꾼 것을 흉내 낸다.
              managerRunFixture(
                roleInRun: role,
                status: fetches <= 1 ? RunStatus.idle : RunStatus.confirmed,
                confirmed: fetches > 1,
              ),
            ];
          }),
          rosterProvider.overrideWith(
            (ref) async => const RosterResponse(
              runId: 'run-1',
              busNo: '3호차',
              direction: RunDirection.toAcademy,
              counts: RosterCounts(
                boarded: 0,
                waiting: 0,
                noShow: 0,
                absentN: 0,
              ),
              stops: [],
            ),
          ),
          notificationRepositoryProvider.overrideWithValue(notifications),
        ],
        child: const BaraedaManagerApp(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(BaraedaTabBar)),
    );
  }

  testWidgets('동승자가 명단 탭에 머문 채 30초가 지나면 확정된 회차가 목록에 잡힌다', (tester) async {
    final container = await pump(tester, UserRole.escort);
    // 홈 탭은 아직 한 번도 열리지 않았다 — 홈의 타이머에 기댈 수 없다.
    expect(find.byType(ManagerHomeScreen), findsNothing);
    expect(container.read(focusRunProvider), isNull);
    final before = notifications.requests.length;

    await tester.pump(todayRunsRefreshInterval);
    await tester.pumpAndSettle();

    expect(fetches, 2);
    expect(container.read(focusRunProvider)?.runId, 'run-1');
    expect(notifications.requests.length, greaterThan(before));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('앱이 돌아오면 목록 · 알림을 다시 받고 실시간 재접속 신호를 한 번 올린다', (tester) async {
    final container = await pump(tester, UserRole.escort);
    final before = notifications.requests.length;
    expect(container.read(appResumedProvider), 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(fetches, 2);
    expect(notifications.requests.length, greaterThan(before));
    expect(container.read(appResumedProvider), 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('홈 탭을 열어도 한 주기에 목록을 두 번 받지 않는다', (tester) async {
    await pump(tester, UserRole.driver);
    expect(find.byType(ManagerHomeScreen), findsOneWidget);
    expect(fetches, 1);

    await tester.pump(todayRunsRefreshInterval);
    await tester.pumpAndSettle();

    expect(fetches, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('앱이 돌아와도 홈 탭이 목록을 한 번 더 받지 않는다', (tester) async {
    final container = await pump(tester, UserRole.driver);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(fetches, 2);
    expect(container.read(appResumedProvider), 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
