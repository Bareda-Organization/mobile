import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/role_policy.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';
import 'package:parent_app/features/notifications/presentation/notification_providers.dart';
import 'package:parent_app/features/notifications/presentation/notifications_screen.dart';

import '../../../support/fake_notification_repository.dart';

class _FixedClock implements Clock {
  const new(this._value);

  final DateTime _value;

  @override
  DateTime now() => _value;
}

/// 2026-09-30 10:00 KST (수요일).
final _now = DateTime.utc(2026, 9, 30, 1);

/// 한국 시간으로 적은 시각을 서버가 주는 UTC 순간으로.
DateTime _kst(int month, int day, int hour, int minute) =>
    DateTime.utc(2026, month, day, hour - 9, minute);

NotificationItem _item(
  String id, {
  String type = 'signup_decided',
  String? title,
  String body = '본문',
  DateTime? sentAt,
  bool unread = true,
  String? studentName,
}) => NotificationItem(
  notificationId: id,
  type: type,
  title: title ?? '알림 $id',
  body: body,
  sentAt: sentAt ?? _kst(9, 30, 8, 37),
  popup: false,
  studentName: studentName,
  readAt: unread ? null : _kst(9, 30, 9, 0),
);

/// 최신순 [count] 건 — 홀수 번호는 읽음.
List<NotificationItem> _many(int count) => [
  for (var i = 0; i < count; i++)
    _item(
      'n-$i',
      sentAt: _kst(9, 30, 9, 0).subtract(Duration(minutes: i)),
      unread: i.isEven,
    ),
];

Future<({List<String> pushed, ProviderContainer container})> _pump(
  WidgetTester tester,
  FakeNotificationRepository repository, {
  ThemeData? theme,
  UserRole? role,
}) async {
  final pushed = <String>[];
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const NotificationsScreen()),
      for (final path in [AppRoutes.liveMap, AppRoutes.schedule])
        GoRoute(
          path: path,
          builder: (_, _) {
            pushed.add(path);
            return const Scaffold(body: Text('도착'));
          },
        ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      // 종류를 바꿔 다시 그릴 때 앞 회차의 상태가 남지 않게 매번 새 범위로 만든다.
      key: UniqueKey(),
      overrides: [
        notificationRepositoryProvider.overrideWithValue(repository),
        clockProvider.overrideWithValue(_FixedClock(_now)),
        if (role != null)
          roleCapabilitiesProvider.overrideWithValue(RoleCapabilities.of(role)),
      ],
      child: MaterialApp.router(
        theme: theme ?? BaraedaTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    pushed: pushed,
    container: ProviderScope.containerOf(
      tester.element(find.byType(NotificationsScreen)),
    ),
  );
}

void main() {
  group('목록', () {
    testWidgets('날짜 머리 아래에 행이 시각과 함께 묶인다', (tester) async {
      final repository = FakeNotificationRepository([
        _item('today', title: '오늘 알림', sentAt: _kst(9, 30, 8, 37)),
        _item('yesterday', title: '어제 알림', sentAt: _kst(9, 29, 14, 5)),
        _item('older', title: '지난 알림', sentAt: _kst(9, 28, 7, 0)),
      ]);
      await _pump(tester, repository);

      expect(find.text('오늘'), findsOneWidget);
      expect(find.text('어제'), findsOneWidget);
      expect(find.text('9월 28일(월)'), findsOneWidget);
      // 머리 오른쪽에 날짜 — 오늘은 요일까지, 어제는 날짜만(시안).
      expect(find.text('9월 30일 (수)'), findsOneWidget);
      expect(find.text('9월 29일'), findsOneWidget);
      expect(find.text('8:37'), findsOneWidget);
      // 오늘이 아닌 알림은 시각 앞에 날짜가 붙는다(Ruling 835).
      expect(find.text('9월 29일 14:05'), findsOneWidget);
      // 위에서 아래로 오늘 → 어제 → 지난 날짜 순서.
      expect(
        tester.getTopLeft(find.text('오늘')).dy,
        lessThan(tester.getTopLeft(find.text('어제')).dy),
      );
      expect(
        tester.getTopLeft(find.text('어제')).dy,
        lessThan(tester.getTopLeft(find.text('9월 28일(월)')).dy),
      );
    });

    // 시안 `notifications` — 행마다 종류 알약(▶ 지연 · ● 하차 …)이 시각 옆에 있다. 제목과 같은 말이 겹치지 않게
    // 알림 제목은 서버 문구 그대로 두고 알약만 짧은 종류 이름이다.
    testWidgets('종류 알약이 제목과 따로 있고 제목은 서버 문구 그대로다', (tester) async {
      final repository = FakeNotificationRepository([
        _item(
          '1',
          type: 'arrive',
          title: '곧 도착합니다',
          body: '김철수 학생이 탄 버스가 곧 도착합니다.',
        ),
      ]);
      await _pump(tester, repository);

      expect(find.text('곧 도착합니다'), findsOneWidget);
      expect(find.text('곧 도착'), findsOneWidget, reason: '종류 알약');
    });

    // ATT-03 — 알림에는 자녀 이름이 반드시 보여야 한다. 시안은 제목 뒤가 아니라 종류 · 시각 줄 끝에 둔다.
    testWidgets('학부모는 자녀 이름이 종류 · 시각 줄 끝에 붙는다 — 이름이 없는 알림은 그 칸이 없다(ATT-03)', (
      tester,
    ) async {
      final repository = FakeNotificationRepository([
        _item('1', title: '미승차 안내', body: '버스가 출발했습니다.', studentName: '김철수'),
        _item('2', title: '승하차 안내', body: '버스에 탑승했습니다.'),
      ]);
      await _pump(tester, repository, role: UserRole.parent);

      expect(find.text('미승차 안내'), findsOneWidget, reason: '제목은 그대로');
      expect(find.text('· 김철수'), findsOneWidget);
      expect(find.textContaining('· '), findsOneWidget, reason: '이름 없는 행에는 없다');
    });

    testWidgets('학생은 본인 알림이라 이름을 붙이지 않는다', (tester) async {
      final repository = FakeNotificationRepository([
        _item('1', title: '곧 도착', body: '곧 도착합니다.', studentName: '김철수'),
      ]);
      await _pump(tester, repository, role: UserRole.student);

      expect(find.text('· 김철수'), findsNothing);
    });

    testWidgets('낭독 — 안 읽음 · 중요 · 종류 · 제목 · 본문 · 시각을 한 번에', (tester) async {
      final handle = tester.ensureSemantics();
      final repository = FakeNotificationRepository([
        _item(
          '1',
          type: 'no_show',
          title: '미승차 안내',
          body: '김철수 학생이 탑승하지 않았습니다.',
        ),
      ]);
      await _pump(tester, repository);

      expect(
        find.bySemanticsLabel(
          '안 읽음, 중요, 미승차, 미승차 안내, 김철수 학생이 탑승하지 않았습니다., 오전 8시 37분',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('걸러 보기', () {
    testWidgets('[안 읽음] 은 unread_only 로 요청하고 읽은 알림은 안 보인다', (tester) async {
      final repository = FakeNotificationRepository(_many(4));
      await _pump(tester, repository);
      expect(repository.requests.last.unreadOnly, isFalse);
      expect(find.text('알림 n-1'), findsOneWidget); // 읽음

      await tester.tap(find.textContaining('안 읽음'));
      await tester.pumpAndSettle();

      expect(repository.requests.last.unreadOnly, isTrue);
      expect(find.text('알림 n-0'), findsOneWidget);
      expect(find.text('알림 n-1'), findsNothing);

      await tester.tap(find.text('전체'));
      await tester.pumpAndSettle();
      expect(repository.requests.last.unreadOnly, isFalse);
      expect(find.text('알림 n-1'), findsOneWidget);
    });
  });

  group('다음 쪽 · 새로고침', () {
    testWidgets('스크롤이 끝에 닿으면 다음 쪽을 자동으로 받는다', (tester) async {
      final repository = FakeNotificationRepository(_many(45));
      await _pump(tester, repository);
      expect(repository.requests.map((r) => r.page), [0]);
      expect(find.text('알림 n-20', skipOffstage: false), findsNothing);

      await tester.fling(find.byType(ListView), const Offset(0, -4000), 3000);
      await tester.pumpAndSettle();

      expect(
        repository.requests.map((r) => r.page),
        containsAllInOrder([0, 1]),
      );
      await tester.scrollUntilVisible(
        find.text('알림 n-20'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('알림 n-20'), findsOneWidget);
    });

    testWidgets('[더 보기] 버튼은 없다', (tester) async {
      await _pump(tester, FakeNotificationRepository(_many(45)));

      expect(find.text('더 보기'), findsNothing);
    });

    testWidgets('마지막 쪽 뒤에는 더 요청하지 않는다', (tester) async {
      final repository = FakeNotificationRepository(_many(30));
      await _pump(tester, repository);

      for (var i = 0; i < 3; i++) {
        await tester.fling(find.byType(ListView), const Offset(0, -4000), 3000);
        await tester.pumpAndSettle();
      }

      expect(repository.requests.map((r) => r.page).toSet(), {0, 1});
    });

    testWidgets('다음 쪽 받기가 실패하면 목록은 그대로이고 [다시 시도] 가 나온다', (tester) async {
      final repository = FakeNotificationRepository(_many(45))
        ..getFailure = null;
      await _pump(tester, repository);
      repository
        ..getFailure = const Failure.network()
        ..failOnPage = 1;

      await tester.fling(find.byType(ListView), const Offset(0, -4000), 3000);
      await tester.pumpAndSettle();

      expect(find.text('알림 n-19', skipOffstage: false), findsOneWidget);
      expect(find.text('더 불러오지 못했습니다'), findsOneWidget);

      repository.getFailure = null;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('알림 n-20'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('알림 n-20'), findsOneWidget);
    });

    testWidgets('당겨서 새로고침하면 처음부터 다시 받는다', (tester) async {
      final repository = FakeNotificationRepository(_many(3));
      await _pump(tester, repository);
      expect(repository.requests, hasLength(1));

      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      expect(repository.requests, hasLength(2));
      expect(repository.requests.last.page, 0);
    });
  });

  group('읽음 처리', () {
    testWidgets('안 읽은 행을 누르면 읽음 처리되고 안 읽은 수가 줄어든다', (tester) async {
      final repository = FakeNotificationRepository(_many(4)); // 안 읽음 2
      final (:pushed, :container) = await _pump(tester, repository);
      expect(container.read(notificationFeedProvider).value!.unreadCount, 2);

      await tester.tap(find.text('알림 n-0'));
      await tester.pumpAndSettle();

      expect(repository.marked, ['n-0']);
      expect(container.read(notificationFeedProvider).value!.unreadCount, 1);
      expect(pushed, isEmpty); // signup_decided 는 갈 화면이 없다
      expect(find.byKey(NotificationTile.unreadDotKey), findsOneWidget);
    });

    testWidgets('읽음 처리가 실패해도 예외가 새지 않고 안내한다(F05-13)', (tester) async {
      final repository = FakeNotificationRepository(_many(2))
        ..markFailure = const Failure.network();
      await _pump(tester, repository);

      await tester.tap(find.text('알림 n-0'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('네트워크 상태를 확인해 주세요'), findsOneWidget);
    });
  });

  // R32 P10 — 알림을 눌러도 읽음 처리만 되고 관련 화면으로 가지 않았다.
  group('알림을 누르면 관련 화면으로 간다', () {
    testWidgets('승차·하차·미승차·도착·지연·운행 시작·노선 변경은 실시간 지도로 간다', (tester) async {
      for (final type in [
        'boarding',
        'alighting',
        'no_show',
        'arrive',
        'delay',
        'run_started',
        'route_changed',
      ]) {
        final repository = FakeNotificationRepository([
          _item('n-1', type: type),
        ]);
        final result = await _pump(tester, repository);
        await tester.tap(find.text('알림 n-1'));
        await tester.pumpAndSettle();

        expect(result.pushed, [AppRoutes.liveMap], reason: type);
        expect(repository.marked, ['n-1'], reason: '$type 은 읽음 처리도 한다');
      }
    });

    testWidgets('변경 결과 알림은 일정(신청 이력) 화면으로 간다', (tester) async {
      final result = await _pump(
        tester,
        FakeNotificationRepository([_item('n-1', type: 'change_decided')]),
      );
      await tester.tap(find.text('알림 n-1'));
      await tester.pumpAndSettle();

      expect(result.pushed, [AppRoutes.schedule]);
    });

    testWidgets('이미 읽은 알림도 눌러서 갈 수 있고 다시 읽음 처리하지 않는다', (tester) async {
      final repository = FakeNotificationRepository([
        _item('n-1', type: 'delay', unread: false),
      ]);
      final result = await _pump(tester, repository);
      await tester.tap(find.text('알림 n-1'));
      await tester.pumpAndSettle();

      expect(result.pushed, [AppRoutes.liveMap]);
      expect(repository.marked, isEmpty);
    });
  });

  group('빈 화면 · 오류 화면', () {
    testWidgets('알림이 없으면 빈 화면이다', (tester) async {
      await _pump(tester, FakeNotificationRepository(const []));

      expect(find.text('새 알림이 없어요'), findsOneWidget);
    });

    testWidgets('안 읽은 알림이 없으면 그 걸러 보기에 맞는 빈 화면이다', (tester) async {
      await _pump(
        tester,
        FakeNotificationRepository([_item('1', unread: false)]),
      );
      await tester.tap(find.textContaining('안 읽음'));
      await tester.pumpAndSettle();

      expect(find.text('안 읽은 알림이 없어요'), findsOneWidget);
      expect(find.text('알림 1'), findsNothing);
    });

    testWidgets('처음 받기가 실패하면 오류 화면과 [다시 시도] 가 나오고 다시 받는다', (tester) async {
      final repository = FakeNotificationRepository(_many(2))
        ..getFailure = const Failure.network();
      await _pump(tester, repository);

      expect(find.text('알림을 불러오지 못했어요'), findsOneWidget);

      repository.getFailure = null;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(find.text('알림을 불러오지 못했어요'), findsNothing);
      expect(find.text('알림 n-0'), findsOneWidget);
    });
  });
  // R48 시안 `notifications*` — 머리 아래 "최근 14일 · 자녀 이름들"
  // (학생은 "최근 14일"), 안 읽음 알약에는 서버가 센 수.
  group('R48 구성', () {
    Future<void> pumpAs(
      WidgetTester tester,
      FakeNotificationRepository repository, {
      required bool parent,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            notificationRepositoryProvider.overrideWithValue(repository),
            clockProvider.overrideWithValue(_FixedClock(_now)),
            roleCapabilitiesProvider.overrideWithValue(
              RoleCapabilities.of(parent ? UserRole.parent : UserRole.student),
            ),
            myStudentsProvider.overrideWith(
              (ref) async => [
                Student(
                  studentId: 's-1',
                  name: '이하준',
                  linkedAt: DateTime(2026),
                ),
                Student(
                  studentId: 's-2',
                  name: '이서연',
                  linkedAt: DateTime(2026),
                ),
              ],
            ),
          ],
          child: MaterialApp(
            theme: BaraedaTheme.light(),
            home: const NotificationsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('학부모는 머리 아래에 최근 14일과 연결된 자녀 이름이 있다', (tester) async {
      await pumpAs(tester, FakeNotificationRepository(_many(2)), parent: true);

      expect(find.text('최근 14일 · 이하준 · 이서연'), findsOneWidget);
    });

    testWidgets('학생은 자녀 이름 없이 최근 14일만 있다', (tester) async {
      await pumpAs(
        tester,
        FakeNotificationRepository(_many(2)),
        parent: false,
      );

      expect(find.text('최근 14일'), findsOneWidget);
      expect(find.textContaining('이하준'), findsNothing);
    });

    testWidgets('[안 읽음] 알약에 서버가 센 안 읽은 수가 붙는다', (tester) async {
      await pumpAs(tester, FakeNotificationRepository(_many(4)), parent: true);

      // `_many(4)` 는 짝수 번째 둘이 안 읽음이다.
      expect(find.text('안 읽음 2'), findsOneWidget);
      expect(find.text('전체'), findsOneWidget);
    });
  });
}
