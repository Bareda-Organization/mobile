import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_core/testing.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_screen.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/notifications/presentation/notification_providers.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/roster/presentation/roster_screen.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

import '../../support/manager_run_fixture.dart';

class _NoSample implements PositionSource {
  @override
  PositionAvailability get availability => PositionAvailability.available;

  @override
  PositionSample? sample() => null;

  @override
  Future<void> recheck() async {}

  @override
  void start() {}

  @override
  void stop() {}

  @override
  Future<PositionSample?> sampleOnce({
    Duration timeout = const Duration(seconds: 5),
  }) async => null;
}

const _roster = RosterResponse(
  runId: 'run-1',
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  counts: RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
  stops: [
    RosterStop(stopId: 's1', seq: 1, name: '1번', students: []),
    RosterStop(stopId: 's2', seq: 2, name: '학원', students: []),
  ],
);

NotificationItem _unread(String id) => NotificationItem(
  notificationId: id,
  type: 'route_changed',
  title: '노선이 바뀌었어요',
  body: '',
  sentAt: DateTime(2026, 10, 3, 12),
  popup: false,
);

/// 알림 진입점으로 읽히는 것 — 알림 아이콘 · 알림 글자 · 배지 · 아래 탭 막대.
void expectNoNotificationEntry() {
  expect(find.byType(BaraedaTabBar), findsNothing);
  expect(find.byType(BaraedaBadge), findsNothing);
  expect(find.text('알림'), findsNothing);
  expect(
    find.byWidgetPredicate((w) => w is BaraedaIcon && w.name == 'bell'),
    findsNothing,
  );
}

void main() {
  Future<ProviderContainer> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(NeverResolvingTokenStorage()),
          positionSourceProvider.overrideWithValue(_NoSample()),
          notificationRepositoryProvider.overrideWithValue(
            FakeNotificationRepository([
              for (var i = 0; i < 3; i++) _unread('n$i'),
            ]),
          ),
          routeProvider.overrideWith(
            (ref) async => const RouteResponse(stops: []),
          ),
          selectedRunIdProvider.overrideWith((ref) => 'run-1'),
          currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
          todayRunsProvider.overrideWith(
            (ref) async => [
              managerRunFixture(
                status: RunStatus.moving,
                roleInRun: UserRole.driver,
              ),
            ],
          ),
          driveModeRosterProvider.overrideWith((ref) async => _roster),
          rosterProvider.overrideWith((ref) async => _roster),
        ],
        child: MaterialApp(home: home),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    // 안 읽은 알림을 실제로 받아 둔다 — 그래도 운전 화면에는 나오지 않아야 한다.
    await container.read(notificationFeedProvider.future);
    await tester.pump();
    await tester.pump();
    return container;
  }

  testWidgets('기사 운전 화면에는 안 읽은 알림이 있어도 알림 진입점·배지가 없다', (tester) async {
    final container = await pump(tester, const DriveModeScreen());

    expect(container.read(notificationFeedProvider).value?.unreadCount, 3);
    expect(find.text('도착 처리'), findsOneWidget, reason: '운전 화면이 실제로 그려졌다');
    expectNoNotificationEntry();
  });

  testWidgets('기사의 조회 전용 명단에도 알림 진입점·배지가 없다', (tester) async {
    final container = await pump(tester, const RosterScreen(readOnly: true));

    expect(container.read(notificationFeedProvider).value?.unreadCount, 3);
    expect(find.textContaining('조회 전용'), findsWidgets, reason: '명단이 그려졌다');
    expectNoNotificationEntry();
  });
}
