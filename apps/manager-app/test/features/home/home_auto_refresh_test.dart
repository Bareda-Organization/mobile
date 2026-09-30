import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_button.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/home/presentation/home_screen.dart';

import '../../support/manager_run_fixture.dart';

/// F06-13 — 홈 회차 목록은 한 번 받고 고정이라 확정 시각(출발 30분 전)이 지나도 카드가 잠긴 채였고,
/// 비상 버튼도 그 옛 목록으로 판정했다. 서버 배치(30초 폴링)와 같은 주기로 다시 받는다.
void main() {
  Widget app(Widget home, {required int Function() fetches}) => ProviderScope(
    overrides: [
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
    expect(find.textContaining('확정 후 열립니다'), findsOneWidget);

    await tester.pump(todayRunsRefreshInterval);
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.textContaining('확정 후 열립니다'), findsNothing);
    expect(
      tester.widget<RunSummaryCard>(find.byType(RunSummaryCard)).onTap,
      isNotNull,
    );
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
}
