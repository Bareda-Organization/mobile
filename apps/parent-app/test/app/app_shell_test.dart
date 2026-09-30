import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/app.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/app/router.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/devices/data/device_registration_storage.dart';
import 'package:parent_app/core/runs/presentation/run_providers.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';
import 'package:parent_app/features/auth/presentation/login_screen.dart';
import 'package:parent_app/features/auth/presentation/pending_approval_screen.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';
import 'package:parent_app/features/notifications/domain/notification_item.dart';
import 'package:parent_app/features/notifications/presentation/notifications_screen.dart';
import 'package:parent_app/features/settings/domain/notification_settings.dart';
import 'package:parent_app/features/settings/presentation/settings_providers.dart';
import 'package:parent_app/features/settings/presentation/settings_screen.dart';

import '../support/fake_notification_repository.dart';
import '../support/fake_token_storage.dart';

class _FakeDeviceRegistrationStorage extends DeviceRegistrationStorage {
  @override
  Future<String> readOrCreateDeviceId() async => 'device-1';

  @override
  Future<String?> readToken() async => null;

  @override
  Future<void> saveToken(String token) async {}

  @override
  Future<void> clearToken() async {}
}

NotificationItem _item(String id, {bool unread = true}) => NotificationItem(
  notificationId: id,
  type: 'signup_decided',
  title: '알림 $id',
  body: '본문',
  sentAt: DateTime.utc(2026, 9, 29, 23, 37),
  popup: false,
  readAt: unread ? null : DateTime.utc(2026, 9, 30),
);

/// 앱 아래 탭 막대(`NavigationBar`) — R44. 로그인 뒤 화면에만 있고, 로그인·가입·대기·차단 화면과
/// 탭 위에 얹은 하위 화면(지도·일정·비밀번호 변경 …)에는 없다.
void main() {
  Future<FakeNotificationRepository> pumpApp(
    WidgetTester tester, {
    UserRole? role = UserRole.parent,
    AccountStatus status = AccountStatus.active,
    List<NotificationItem>? items,
  }) async {
    final repository = FakeNotificationRepository(
      items ?? [_item('a'), _item('b'), _item('c', unread: false)],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          currentUserRoleProvider.overrideWith((ref) => role),
          currentAccountStatusProvider.overrideWith((ref) => status),
          notificationRepositoryProvider.overrideWithValue(repository),
          myStudentsProvider.overrideWith((ref) async => const []),
          myStudentIdProvider.overrideWith((ref) async => 's-1'),
          runsForStudentProvider.overrideWith((ref, id) async => const []),
          deviceRegistrationStorageProvider.overrideWithValue(
            _FakeDeviceRegistrationStorage(),
          ),
          notificationSettingsProvider.overrideWith(
            (ref) async => const NotificationSettings(
              arrive: true,
              boarding: true,
              noShow: true,
            ),
          ),
        ],
        child: const BaraedaParentApp(),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Finder tabBar() => find.byType(NavigationBar);

  group('탭이 나오는 곳', () {
    testWidgets('로그인 뒤에는 [홈] [알림] [설정] 탭 3개가 있다', (tester) async {
      await pumpApp(tester);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tabBar(), findsOneWidget);
      final destinations = tester.widgetList<NavigationDestination>(
        find.byType(NavigationDestination),
      );
      expect(destinations.map((d) => d.label), ['홈', '알림', '설정']);
    });

    testWidgets('학생 계정도 같은 탭 3개다', (tester) async {
      await pumpApp(tester, role: UserRole.student);

      expect(
        tester
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .map((d) => d.label),
        ['홈', '알림', '설정'],
      );
    });

    testWidgets('로그인 화면에는 탭이 없다', (tester) async {
      await pumpApp(tester, role: null);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(tabBar(), findsNothing);
    });

    testWidgets('승인 대기 화면에는 탭이 없다', (tester) async {
      await pumpApp(tester, status: AccountStatus.pending);

      expect(find.byType(PendingApprovalScreen), findsOneWidget);
      expect(tabBar(), findsNothing);
    });

    testWidgets('탭 위에 얹은 하위 화면에는 탭이 없고 뒤로 가면 탭이 돌아온다', (tester) async {
      await pumpApp(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );

      unawaited(
        container.read(routerProvider).push<void>(AppRoutes.passwordChange),
      );
      await tester.pumpAndSettle();
      expect(tabBar(), findsNothing);

      container.read(routerProvider).pop();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tabBar(), findsOneWidget);
    });
  });

  group('탭 이동', () {
    testWidgets('[알림] 탭은 알림 화면을, [설정] 탭은 설정 화면을 연다', (tester) async {
      await pumpApp(tester);

      await tester.tap(
        find.descendant(of: tabBar(), matching: find.text('알림')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.text('알림 a'), findsOneWidget);

      await tester.tap(
        find.descendant(of: tabBar(), matching: find.text('설정')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tester.tap(find.descendant(of: tabBar(), matching: find.text('홈')));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('홈에는 알림 목록이 없다', (tester) async {
      await pumpApp(tester);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('알림 a'), findsNothing);
      expect(find.text('새 알림이 없습니다'), findsNothing);
      // 탭 막대 밖에서 '알림' 머리말이 하나도 없다.
      expect(
        find.descendant(
          of: find.byType(HomeScreen),
          matching: find.text('알림'),
        ),
        findsNothing,
      );
    });

    testWidgets('탭을 오가도 알림 목록이 다시 받아지지 않는다', (tester) async {
      final repository = await pumpApp(tester);
      await tester.tap(
        find.descendant(of: tabBar(), matching: find.text('알림')),
      );
      await tester.pumpAndSettle();
      final before = repository.requests.length;

      await tester.tap(find.descendant(of: tabBar(), matching: find.text('홈')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: tabBar(), matching: find.text('알림')),
      );
      await tester.pumpAndSettle();

      expect(repository.requests.length, before);
    });
  });

  group('알림 탭 배지', () {
    testWidgets('안 읽은 수(서버 unread_count)가 배지로 나온다', (tester) async {
      await pumpApp(tester);

      expect(
        find.descendant(of: tabBar(), matching: find.text('2')),
        findsOneWidget,
      );
    });

    testWidgets('안 읽은 알림이 없으면 배지가 없다', (tester) async {
      await pumpApp(tester, items: [_item('c', unread: false)]);

      expect(
        find.descendant(of: tabBar(), matching: find.byType(Badge)),
        findsOneWidget,
      );
      expect(
        tester.widget<Badge>(find.byType(Badge)).isLabelVisible,
        isFalse,
      );
    });

    testWidgets('99건이 넘으면 99+ 로 줄인다', (tester) async {
      await pumpApp(
        tester,
        items: [for (var i = 0; i < 120; i++) _item('n-$i')],
      );

      expect(
        find.descendant(of: tabBar(), matching: find.text('99+')),
        findsOneWidget,
      );
    });

    testWidgets('알림을 읽으면 배지가 줄어든다', (tester) async {
      await pumpApp(tester);
      await tester.tap(
        find.descendant(of: tabBar(), matching: find.text('알림')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('알림 a'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: tabBar(), matching: find.text('1')),
        findsOneWidget,
      );
    });

    testWidgets('낭독 문구에 안 읽은 건수가 실린다', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);

      expect(find.bySemanticsLabel(RegExp('안 읽은 알림 2건')), findsWidgets);
      handle.dispose();
    });
  });

  // F05-06 — 푸시 SDK 가 없어 앱 안 갱신이 유일한 통지 수단이다. 알림 탭을 열지 않아도 배지는 최신이어야 한다.
  group('자동 갱신', () {
    testWidgets('30초가 지나면 알림을 다시 받아 배지가 최신이 된다', (tester) async {
      final repository = await pumpApp(tester);
      final before = repository.requests.length;

      await repository.markRead('a'); // 서버 쪽에서 읽음 처리됨
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();

      expect(repository.requests.length, greaterThan(before));
      expect(
        find.descendant(of: tabBar(), matching: find.text('1')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('앱이 백그라운드에서 돌아오면 알림을 다시 받는다', (tester) async {
      final repository = await pumpApp(tester);
      final before = repository.requests.length;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(repository.requests.length, greaterThan(before));
    });
  });
}
