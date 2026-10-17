import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_core/testing.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/me_provider.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/features/home/data/manager_run_api.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/data/run_summary_store.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/home/presentation/home_screen.dart';

import '../../support/fake_run_summary_store.dart';
import '../../support/manager_run_fixture.dart';

/// [offline] 이 참이면 연결이 닿지 않는 서버 — 기본은 오늘 회차 하나를 준다.
class _FlakyRunApi extends ManagerRunApi {
  new() : super(dio: Dio());

  bool offline = false;

  @override
  Future<List<ManagerRun>> fetchRuns({DateTime? date}) async {
    if (offline) {
      throw DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.connectionError,
      );
    }
    return [managerRunFixture()];
  }
}

/// 통신이 끊겨 기기에 저장한 오늘 목록을 보여 주는 동안 홈이 그 사실을 알린다(NFR-01).
/// 연결되어 새로 받으면 알림이 사라진다.
void main() {
  final now = DateTime(2026, 10, 3, 12, 14);

  testWidgets('저장해 둔 목록으로 보는 동안 홈에 그 사실과 받은 시각이 보이고, 새로 받으면 사라진다', (
    tester,
  ) async {
    final api = _FlakyRunApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(FixedClock(now)),
          managerRunApiProvider.overrideWithValue(api),
          runSummaryStoreProvider.overrideWithValue(FakeRunSummaryStore()),
          currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
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
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: AppRoutes.home,
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (_, _) => const ManagerHomeScreen(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('저장해 둔 목록'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ManagerHomeScreen)),
    );
    api.offline = true;
    container.invalidate(todayRunsProvider);
    await tester.pumpAndSettle();

    expect(find.text('저장해 둔 목록으로 보고 있어요'), findsOneWidget);
    expect(find.textContaining('12:14'), findsWidgets);
    expect(find.textContaining('연결되면 자동으로 다시 불러와요'), findsOneWidget);

    api.offline = false;
    container.invalidate(todayRunsProvider);
    await tester.pumpAndSettle();

    expect(find.textContaining('저장해 둔 목록'), findsNothing);
  });
}
