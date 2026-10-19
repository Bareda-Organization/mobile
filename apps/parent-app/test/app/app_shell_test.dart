import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_core/testing.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/app.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/app_shell.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/app/router.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/network/network_status.dart';
import 'package:parent_app/core/runs/presentation/run_providers.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';
import 'package:parent_app/features/auth/presentation/login_screen.dart';
import 'package:parent_app/features/auth/presentation/pending_approval_screen.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';
import 'package:parent_app/features/notifications/presentation/notifications_screen.dart';
import 'package:parent_app/features/schedule/presentation/schedule_screen.dart';
import 'package:parent_app/features/settings/domain/notification_settings.dart';
import 'package:parent_app/features/settings/presentation/settings_providers.dart';
import 'package:parent_app/features/settings/presentation/settings_screen.dart';

/// 소켓 없이 "앱 복귀 때 재연결을 요청하는가" 만 보려는 가짜 클라이언트 — 세션 시작이 읽는 `sessionExpired` 와
/// 복귀 때 부르는 `reconnectNow` 만 구현한다.
class _FakeWsClient implements BaraedaWebSocketClient {
  @override
  bool get isRenewing => false;

  int reconnectNowCalls = 0;
  int connectCalls = 0;
  int disconnectCalls = 0;

  @override
  WsConnectionState state = WsConnectionState.connected;

  @override
  Stream<void> get sessionExpired => const Stream<void>.empty();

  @override
  void connect() {
    connectCalls++;
    state = WsConnectionState.connected;
  }

  @override
  void disconnect() {
    disconnectCalls++;
    state = WsConnectionState.disconnected;
  }

  @override
  void reconnectNow() => reconnectNowCalls++;

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('이 시험의 관심사가 아니다: ${invocation.memberName}');
}

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

/// 앱 아래 탭 막대(`BaraedaTabBar`) — 로그인 뒤 화면에만 있고, 로그인·가입·대기·차단 화면과
/// 탭 위에 얹은 하위 화면(지도·비밀번호 변경·요일별 주소 …)에는 없다.
/// 학부모는 `홈 · 일정 · 알림 · 설정`, 학생은 `내 버스 · 알림 · 설정`(`Ruling 826`).
void main() {
  Future<FakeNotificationRepository> pumpApp(
    WidgetTester tester, {
    UserRole? role = UserRole.parent,
    AccountStatus status = AccountStatus.active,
    List<NotificationItem>? items,
    List<Override> extraOverrides = const [],
  }) async {
    final repository = FakeNotificationRepository(
      items ?? [_item('a'), _item('b'), _item('c', unread: false)],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...extraOverrides,
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

  Finder tabBar() => find.byType(BaraedaTabBar);

  List<String> tabLabels(WidgetTester tester) =>
      tester.widget<BaraedaTabBar>(tabBar()).items.map((i) => i.label).toList();

  group('탭이 나오는 곳', () {
    testWidgets('학부모는 [홈] [일정] [알림] [설정] 탭 4개다 — 일정이 새 탭이다', (tester) async {
      await pumpApp(tester);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tabBar(), findsOneWidget);
      expect(tabLabels(tester), ['홈', '일정', '알림', '설정']);
    });

    testWidgets('학생은 [내 버스] [알림] [설정] 탭 3개다 — 일정 탭이 없다', (tester) async {
      await pumpApp(tester, role: UserRole.student);

      expect(tabLabels(tester), ['내 버스', '알림', '설정']);
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
    testWidgets('[일정] 탭은 일정 화면을 연다(학부모)', (tester) async {
      await pumpApp(tester);

      await tester.tap(
        find.descendant(of: tabBar(), matching: find.text('일정')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ScheduleScreen), findsOneWidget);
      expect(tabBar(), findsOneWidget);
    });

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
      expect(find.text('새 알림이 없어요'), findsNothing);
      // 탭 막대 밖에서 '알림' 머리말이 하나도 없다.
      expect(
        find.descendant(of: find.byType(HomeScreen), matching: find.text('알림')),
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

      // 안 읽은 알림이 없으면 어느 탭에도 건수가 붙지 않는다.
      expect(
        tester
            .widget<BaraedaTabBar>(tabBar())
            .items
            .every((item) => item.badge == 0 && !item.dotBadge),
        isTrue,
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

      expect(find.bySemanticsLabel(RegExp('새 알림 2건')), findsWidgets);
      handle.dispose();
    });
  });

  // F05-06 — 푸시 SDK 가 없어 앱 안 갱신이 유일한 통지 수단이다. 알림 탭을 열지 않아도 배지는 최신이어야 한다.
  // 앱이 백그라운드에서 돌아오면 끊겨 대기 중인 실시간 연결을 다음 재연결 타이머(최대 30초)를
  // 기다리지 않고 바로 다시 붙인다. 지금까지는 알림 목록(REST)만 다시 받았다.
  testWidgets('앱이 백그라운드에서 돌아오면 실시간 연결을 바로 다시 붙이게 요청한다', (tester) async {
    final client = _FakeWsClient();
    await pumpApp(
      tester,
      extraOverrides: [webSocketClientProvider.overrideWithValue(client)],
    );
    expect(client.reconnectNowCalls, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(client.reconnectNowCalls, 1);
  });

  // 백그라운드에서 60초가 지나면 실시간 연결을 끊어 서버 세션과 배터리를 아끼고, 복귀하면 다시 붙인다.
  // 다시 붙으면 지도(`LiveMapNotifier`)가 같은 목적지를 구독하고 REST 스냅샷을
  // 다시 읽는다(live_map_screen_test).
  group('백그라운드 60초 — 실시간 연결 끊기(M-5)', () {
    const limit = Duration(seconds: 60);

    testWidgets('60초가 지나면 연결을 끊고 복귀하면 다시 붙인다', (tester) async {
      final client = _FakeWsClient();
      await pumpApp(
        tester,
        extraOverrides: [webSocketClientProvider.overrideWithValue(client)],
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(limit - const Duration(seconds: 1));
      expect(client.disconnectCalls, 0, reason: '60초 전에는 유지한다');

      await tester.pump(const Duration(seconds: 1));
      expect(client.disconnectCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(client.connectCalls, 1);
      expect(client.reconnectNowCalls, 0);
    });

    testWidgets('60초 안에 돌아오면 끊지 않고 일반 복귀 처리만 한다', (tester) async {
      final client = _FakeWsClient();
      await pumpApp(
        tester,
        extraOverrides: [webSocketClientProvider.overrideWithValue(client)],
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(limit * 2);

      expect(client.disconnectCalls, 0);
      expect(client.connectCalls, 0);
      expect(client.reconnectNowCalls, 1);
    });

    testWidgets('연결이 없던 앱(지도 밖)은 복귀해도 연결을 새로 열지 않는다', (tester) async {
      final client = _FakeWsClient()..state = WsConnectionState.disconnected;
      await pumpApp(
        tester,
        extraOverrides: [webSocketClientProvider.overrideWithValue(client)],
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(limit);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(client.disconnectCalls, 0);
      expect(client.connectCalls, 0);
    });
  });

  // 와이파이가 돌아와도 재연결 대기(최대 30초)가
  // 끝나야 실시간 연결이 붙었다. 이 앱은 REST 성공이 사실상의 망 복귀
  // 신호이므로(`NetworkStatusNotifier`), 끊김(오프라인)에서 서버에 다시 닿는
  // 순간 연결을 바로 다시 붙이게 요청한다.
  group('망 복귀 — 실시간 연결을 바로 다시 붙인다(C-10)', () {
    testWidgets('서버에 못 닿다가(오프라인) 다시 닿으면 재연결을 요청한다', (tester) async {
      final client = _FakeWsClient();
      await pumpApp(
        tester,
        extraOverrides: [webSocketClientProvider.overrideWithValue(client)],
      );
      final network = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      ).read(networkStatusProvider.notifier);

      // 중간에 확인(expect)이 끼어 한 번에 이을 수 없다.
      // ignore: cascade_invocations
      network.markUnreachable();
      await tester.pump();
      expect(client.reconnectNowCalls, 0, reason: '끊긴 순간에는 요청하지 않는다');

      network.markReachable();
      await tester.pump();

      expect(client.reconnectNowCalls, 1);
    });

    testWidgets('계속 닿고 있는 동안의 성공 응답은 재연결을 요청하지 않는다', (tester) async {
      final client = _FakeWsClient();
      await pumpApp(
        tester,
        extraOverrides: [webSocketClientProvider.overrideWithValue(client)],
      );
      ProviderScope.containerOf(tester.element(find.byType(AppShell)))
          .read(networkStatusProvider.notifier)
        ..markReachable()
        ..markReachable();
      await tester.pump();

      expect(client.reconnectNowCalls, 0);
    });
  });

  group('자동 갱신', () {
    testWidgets('90초가 지나면 알림을 다시 받아 배지가 최신이 된다', (tester) async {
      final repository = await pumpApp(tester);
      final before = repository.requests.length;

      await repository.markRead('a'); // 서버 쪽에서 읽음 처리됨
      await tester.pump(const Duration(seconds: 91));
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
