import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/me_provider.dart';
import 'package:manager_app/core/run/manager_run_channel.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_button.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/home/presentation/home_screen.dart';
import 'package:manager_app/features/home/presentation/widgets/focus_run_card.dart';
import '../../support/fake_notification_repository.dart';
import '../../support/manager_run_fixture.dart';

/// F06-13 — 홈 회차 목록은 한 번 받고 고정이라 확정 시각(출발 30분 전)이 지나도 카드가 잠긴 채였고,
/// 비상 버튼도 그 옛 목록으로 판정했다. 서버 배치(30초 폴링)와 같은 주기로 다시 받는다.
/// 머리줄 부제가 `/me` 를 읽는다 — 이 시험의 관심사가 아니라 실제 서버로 나가지 않게 막는다.
final Override _noMe = meProvider.overrideWith(
  (ref) async => throw StateError('이 시험은 내 정보를 쓰지 않는다'),
);

void main() {
  Widget app(Widget home, {required int Function() fetches}) => ProviderScope(
    overrides: [
      _noMe,
      todayRunsProvider.overrideWith((ref) async {
        final count = fetches();
        // 첫 조회는 확정 전, 그 뒤는 확정 — 서버 배치가 확정 시각에 상태를 바꾼 것을 흉내 낸다.
        return [
          managerRunFixture(
            status: count <= 1 ? RunStatus.idle : RunStatus.confirmed,
            confirmed: count > 1,
          ),
        ];
      }),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => home),
          GoRoute(
            path: AppRoutes.emergency,
            builder: (_, _) => const Text('EMERGENCY_MARKER'),
          ),
        ],
      ),
    ),
  );

  testWidgets('홈이 열려 있는 동안 주기마다 목록을 다시 받아 확정된 카드가 열린다', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      app(const ManagerHomeScreen(), fetches: () => ++calls),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('확정되면 열려요'), findsOneWidget);

    await tester.pump(todayRunsRefreshInterval);
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.textContaining('확정되면 열려요'), findsNothing);
    // 확정된 회차는 큰 카드가 된다.
    expect(find.byType(FocusRunCard), findsOneWidget);
  });

  // R46-FIXRT S-5 — 앱이 백그라운드에서 돌아오면 회차 목록(REST)만이 아니라 실시간 연결도 다시 붙게 신호를 올린다.
  testWidgets('앱이 백그라운드에서 돌아오면 목록을 다시 받고 실시간 연결 복귀 신호도 올린다', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      app(const ManagerHomeScreen(), fetches: () => ++calls),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ManagerHomeScreen)),
    );
    expect(calls, 1);
    expect(container.read(appResumedProvider), 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(container.read(appResumedProvider), 1);
  });

  testWidgets('비상 버튼은 낡은 목록이 아니라 다시 받은 목록으로 신고 가능 여부를 판정한다', (tester) async {
    var calls = 0;
    // 홈 목록은 첫 조회(확정 전) 그대로인데 서버에서는 이미 확정됐다.
    await tester.pumpWidget(
      app(
        Consumer(
          builder: (context, ref, _) {
            final runs = ref.watch(todayRunsProvider).value;
            return Scaffold(body: EmergencyButton(homeRuns: runs));
          },
        ),
        fetches: () => ++calls,
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);

    await tester.tap(find.text('비상'));
    await tester.pumpAndSettle();

    expect(find.text('EMERGENCY_MARKER'), findsOneWidget);
    expect(find.textContaining('확정된 운행이 있을 때'), findsNothing);
  });

  // R46 A — 갱신이 실패해도 마지막으로 받은 목록이 남고, 오류는 목록 위에 따로 알린다.
  testWidgets('R46 주기 갱신이 실패해도 마지막 목록이 남고 오류를 알린다', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _noMe,
          todayRunsProvider.overrideWith((ref) async {
            if (++calls > 1) {
              // Failure 는 Exception/Error 를 상속하지 않는다(다른 시험의 같은 패턴).
              // ignore: only_throw_errors
              throw const NetworkFailure();
            }
            return [managerRunFixture(status: RunStatus.moving)];
          }),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const ManagerHomeScreen(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FocusRunCard), findsOneWidget);

    await tester.pump(todayRunsRefreshInterval);
    await tester.pumpAndSettle();

    expect(find.byType(FocusRunCard), findsOneWidget);
    expect(find.textContaining('최신 운행을 불러오지 못했어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  // R46 B — 아래 탭의 알림 배지는 회차 목록과 같은 주기로 다시 받는다(푸시 SDK 부재).
  testWidgets('R46 홈이 주기마다 알림(탭 배지)도 다시 받는다', (tester) async {
    final notifications = FakeNotificationRepository(const []);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _noMe,
          todayRunsProvider.overrideWith(
            (ref) async => [managerRunFixture(status: RunStatus.moving)],
          ),
          notificationRepositoryProvider.overrideWithValue(notifications),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const ManagerHomeScreen(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = notifications.requests.length;

    await tester.pump(todayRunsRefreshInterval);
    await tester.pumpAndSettle();

    expect(notifications.requests.length, greaterThan(before));
  });
}
