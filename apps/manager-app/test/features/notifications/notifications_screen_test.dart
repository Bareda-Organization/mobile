import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/notifications/presentation/notification_providers.dart';
import 'package:manager_app/features/notifications/presentation/notifications_screen.dart';
import 'package:manager_app/features/notifications/presentation/widgets/notification_bell_button.dart';

import '../../support/fake_notification_repository.dart';

class _FixedClock implements Clock {
  const new(this._value);

  final DateTime _value;

  @override
  DateTime now() => _value;
}

/// 2026-09-30 10:00 KST (수요일).
final _now = DateTime.utc(2026, 9, 30, 1);

DateTime _kst(int month, int day, int hour, int minute) =>
    DateTime.utc(2026, month, day, hour - 9, minute);

NotificationItem _item(
  String id, {
  String type = 'assignment_changed',
  DateTime? sentAt,
  bool unread = true,
  String? runId,
}) => NotificationItem(
  notificationId: id,
  type: type,
  title: '알림 $id',
  body: '본문',
  sentAt: sentAt ?? _kst(9, 30, 8, 37),
  popup: false,
  readAt: unread ? null : _kst(9, 30, 9, 0),
  runId: runId,
);

List<NotificationItem> _many(int count) => [
  for (var i = 0; i < count; i++)
    _item(
      'n-$i',
      sentAt: _kst(9, 30, 9, 0).subtract(Duration(minutes: i)),
      unread: i.isEven,
    ),
];

/// 홈 머리말 배지 → 알림 화면 → 뒤로, 를 실제 라우터로 잇는다.
Future<FakeNotificationRepository> _pump(
  WidgetTester tester,
  List<NotificationItem> items, {
  Widget home = const NotificationsScreen(),
  FakeNotificationRepository? repository,
  List<GoRoute> extraRoutes = const [],
  List<Override> extraOverrides = const [],
}) async {
  final fake = repository ?? FakeNotificationRepository(items);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (_, _) => const NotificationsScreen(),
      ),
      ...extraRoutes,
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        notificationRepositoryProvider.overrideWithValue(fake),
        clockProvider.overrideWithValue(_FixedClock(_now)),
        ...extraOverrides,
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

/// R46 B — 매니저(기사·동승자) 알림 목록. 학부모·학생 앱과 같은 공용 목록 위젯을 쓴다.
void main() {
  testWidgets('종류별 행이 날짜 머리 아래에 보이고 중요 통지(노선 변경)에만 중요 표시가 있다', (tester) async {
    await _pump(tester, [
      _item('1', type: 'route_changed'),
      _item('2'),
      _item('3', type: 'signup_decided', unread: false),
    ]);

    expect(find.text('오늘'), findsOneWidget);
    expect(find.byType(NotificationTile), findsNWidgets(3));
    expect(find.byKey(NotificationTile.importantBarKey), findsOneWidget);
  });

  testWidgets('안 읽은 행을 누르면 읽음 처리하고 안 읽은 수가 준다', (tester) async {
    final fake = await _pump(tester, [_item('1'), _item('2')]);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NotificationsScreen)),
    );
    expect(container.read(notificationFeedProvider).value!.unreadCount, 2);

    await tester.tap(find.text('알림 1'));
    await tester.pumpAndSettle();

    expect(fake.marked, ['1']);
    expect(container.read(notificationFeedProvider).value!.unreadCount, 1);
  });

  testWidgets('[안 읽음] 은 unread_only 로 다시 요청한다', (tester) async {
    final fake = await _pump(tester, _many(4));

    await tester.tap(find.text('안 읽음'));
    await tester.pumpAndSettle();

    expect(fake.requests.last.unreadOnly, isTrue);
  });

  testWidgets('스크롤이 끝에 닿으면 다음 쪽을 받는다', (tester) async {
    final fake = await _pump(tester, _many(45));
    expect(fake.requests.map((r) => r.page), [0]);

    await tester.fling(
      find.byType(ListView).last,
      const Offset(0, -3000),
      3000,
    );
    await tester.pumpAndSettle();

    expect(fake.requests.map((r) => r.page), contains(1));
  });

  testWidgets('알림이 없으면 빈 화면을 보인다', (tester) async {
    await _pump(tester, const []);

    expect(find.text('새 알림이 없습니다'), findsOneWidget);
  });

  testWidgets('첫 쪽 받기가 실패하면 오류 띠와 다시 시도를 보이고 누르면 다시 받는다', (tester) async {
    final fake = FakeNotificationRepository([_item('1')])
      ..getFailure = const NetworkFailure();
    await _pump(tester, const [], repository: fake);
    expect(find.text('알림을 불러오지 못했습니다'), findsOneWidget);

    fake.getFailure = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('알림 1'), findsOneWidget);
  });

  // R46-FUFEAT ③(Ruling 542) — 알림에 회차 식별자(run_id)가 실려 와서, 눌러서 관련 화면으로 간다.
  group('알림 눌러 이동', () {
    final marker = <String, GoRoute>{
      for (final path in [
        AppRoutes.routeMap,
        AppRoutes.driveMode,
        AppRoutes.roster,
      ])
        path: GoRoute(path: path, builder: (_, _) => Text('MARKER $path')),
    };
    Future<ProviderContainer> pumpWith(
      WidgetTester tester,
      List<NotificationItem> items, {
      UserRole role = UserRole.driver,
    }) async {
      await _pump(
        tester,
        items,
        extraRoutes: marker.values.toList(),
        extraOverrides: [currentUserRoleProvider.overrideWith((ref) => role)],
      );
      return ProviderScope.containerOf(
        tester.element(find.byType(NotificationsScreen)),
      );
    }

    testWidgets('노선 변경 알림을 누르면 그 회차를 고르고 노선 화면으로 가며 읽음 처리도 한다', (tester) async {
      final container = await pumpWith(tester, [
        _item('1', type: 'route_changed', runId: 'run-7'),
      ]);

      await tester.tap(find.text('알림 1'));
      await tester.pumpAndSettle();

      expect(find.text('MARKER ${AppRoutes.routeMap}'), findsOneWidget);
      expect(container.read(selectedRunIdProvider), 'run-7');
      expect(container.read(notificationFeedProvider).value!.unreadCount, 0);
    });

    testWidgets('배치 변경 알림은 기사에게 운전 화면으로 간다', (tester) async {
      await pumpWith(tester, [_item('1', runId: 'run-9')]);

      await tester.tap(find.text('알림 1'));
      await tester.pumpAndSettle();

      expect(find.text('MARKER ${AppRoutes.driveMode}'), findsOneWidget);
    });

    testWidgets('배치 변경 알림은 동승자에게 명단 화면으로 간다', (tester) async {
      await pumpWith(tester, [
        _item('1', runId: 'run-9'),
      ], role: UserRole.escort);

      await tester.tap(find.text('알림 1'));
      await tester.pumpAndSettle();

      expect(find.text('MARKER ${AppRoutes.roster}'), findsOneWidget);
    });

    testWidgets('이미 읽은 알림도 눌러서 이동한다', (tester) async {
      final fake = FakeNotificationRepository([
        _item('1', type: 'route_changed', runId: 'run-7', unread: false),
      ]);
      await _pump(
        tester,
        const [],
        repository: fake,
        extraRoutes: marker.values.toList(),
      );

      await tester.tap(find.text('알림 1'));
      await tester.pumpAndSettle();

      expect(find.text('MARKER ${AppRoutes.routeMap}'), findsOneWidget);
      expect(fake.marked, isEmpty);
    });

    testWidgets('회차 식별자가 없는 알림은 읽음 처리만 하고 이동하지 않는다', (tester) async {
      final fake = await _pump(
        tester,
        [_item('1', type: 'route_changed')],
        extraRoutes: marker.values.toList(),
      );

      await tester.tap(find.text('알림 1'));
      await tester.pumpAndSettle();

      expect(fake.marked, ['1']);
      expect(find.byType(NotificationsScreen), findsOneWidget);
    });
  });

  group('홈 머리말 진입 버튼', () {
    testWidgets('안 읽은 수를 배지로 보이고 누르면 알림 화면으로 간다', (tester) async {
      await _pump(
        tester,
        [_item('1'), _item('2'), _item('3', unread: false)],
        home: const Scaffold(body: NotificationBellButton()),
      );
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byType(BaraedaIconButton));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsScreen), findsOneWidget);
    });

    testWidgets('안 읽은 알림이 없으면 배지가 없다', (tester) async {
      await _pump(
        tester,
        [_item('1', unread: false)],
        home: const Scaffold(body: NotificationBellButton()),
      );

      expect(find.byType(Badge), findsOneWidget);
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
    });

    testWidgets('99건이 넘으면 99+ 로 줄인다', (tester) async {
      await _pump(
        tester,
        [for (var i = 0; i < 120; i++) _item('u-$i')],
        home: const Scaffold(body: NotificationBellButton()),
      );
      // 첫 쪽(20건)만 받았어도 배지는 서버가 세는 전체 수를 본다 — 가짜가 전체를 세어 준다.
      expect(find.text('99+'), findsOneWidget);
    });
  });
}
