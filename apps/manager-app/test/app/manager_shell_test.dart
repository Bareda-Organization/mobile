import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/app.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/me_provider.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';

import '../support/fake_notification_repository.dart';
import '../support/fake_token_storage.dart';
import '../support/manager_run_fixture.dart';

/// 아래 탭 틀(`ManagerShell`) — 기사는 3칸(운행 · 알림 · 내 정보), 동승자는 4칸(명단 · 회차 · 알림 · 내
/// 정보)이고
/// 동승자의 첫 화면은 명단이다. 안 읽은 알림 수가 알림 칸 배지로 나온다.
void main() {
  List<Override> overrides(UserRole role) => [
    tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
    currentUserRoleProvider.overrideWith((ref) => role),
    currentAccountStatusProvider.overrideWith((ref) => AccountStatus.active),
    meProvider.overrideWith((ref) async => throw StateError('내 정보 미사용')),
    todayRunsProvider.overrideWith(
      (ref) async => [managerRunFixture(roleInRun: role)],
    ),
    rosterProvider.overrideWith(
      (ref) async => const RosterResponse(
        runId: 'run-1',
        busNo: '3호차',
        direction: RunDirection.toAcademy,
        counts: RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
        stops: [],
      ),
    ),
    selectedRunIdProvider.overrideWith((ref) => 'run-1'),
  ];

  Future<void> pump(
    WidgetTester tester,
    UserRole role, {
    int unread = 0,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides(role),
          notificationRepositoryProvider.overrideWithValue(
            FakeNotificationRepository([
              for (var i = 0; i < unread; i++) _unread('n$i'),
            ]),
          ),
        ],
        child: const BaraedaManagerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> tabLabels(WidgetTester tester) => [
    for (final item
        in tester.widget<BaraedaTabBar>(find.byType(BaraedaTabBar)).items)
      item.label,
  ];

  testWidgets('기사 탭은 운행 · 알림 · 내 정보 3칸이고 첫 화면은 운행이다', (tester) async {
    await pump(tester, UserRole.driver);

    expect(tabLabels(tester), ['운행', '알림', '내 정보']);
    expect(find.text('오늘 운행'), findsOneWidget);
  });

  testWidgets('동승자 탭은 명단 · 회차 · 알림 · 내 정보 4칸이고 첫 화면은 명단이다', (tester) async {
    await pump(tester, UserRole.escort);

    expect(tabLabels(tester), ['명단', '회차', '알림', '내 정보']);
    expect(
      tester.widget<BaraedaTabBar>(find.byType(BaraedaTabBar)).currentIndex,
      0,
    );
  });

  testWidgets('안 읽은 알림 수가 알림 칸 배지로 나온다', (tester) async {
    await pump(tester, UserRole.driver, unread: 2);

    final items = tester
        .widget<BaraedaTabBar>(find.byType(BaraedaTabBar))
        .items;
    expect(items.firstWhere((item) => item.label == '알림').badge, 2);
  });
}

NotificationItem _unread(String id) => NotificationItem(
  notificationId: id,
  type: 'route_changed',
  title: '노선이 바뀌었어요',
  body: '',
  sentAt: DateTime(2026, 10, 3, 12),
  popup: false,
);
