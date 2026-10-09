import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/app.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/app/router.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';

import '../support/fake_token_storage.dart';

/// L5 — 역할 전용 화면에 다른 역할이 닿으면(알림 이동 · 저장된 경로 · 코드 실수) 서버 403 에만 기대지 않고 그
/// 역할의 첫 화면으로 돌려보낸다. 기사 전용(운행 준비 · 운행 중 · 운행 종료 · 조회 전용 명단)과 동승자 전용(지연
/// 알림 · 미승차 연락) 두 갈래다. 두 역할이 함께 쓰는 화면(보고 · 비상 · 대기열 · 노선 지도)은 막지 않는다.
void main() {
  Future<String> landAfterGoing(
    WidgetTester tester, {
    required UserRole role,
    required String target,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          currentUserRoleProvider.overrideWith((ref) => role),
          currentAccountStatusProvider.overrideWith(
            (ref) => AccountStatus.active,
          ),
        ],
        child: const BaraedaManagerApp(),
      ),
    );
    await tester.pumpAndSettle();
    final router = ProviderScope.containerOf(
      tester.element(find.byType(BaraedaManagerApp)),
    ).read(routerProvider)..go(target);
    // 도착한 화면의 로딩 표시가 끝나지 않을 수 있어 pumpAndSettle 대신 시간을 정해 흘린다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    return router.routeInformationProvider.value.uri.path;
  }

  for (final target in [
    AppRoutes.driveMode,
    AppRoutes.runReady,
    AppRoutes.runEnd,
    AppRoutes.rosterView,
  ]) {
    testWidgets('동승자가 기사 전용 $target 에 닿으면 명단으로 돌려보낸다', (tester) async {
      expect(
        await landAfterGoing(tester, role: UserRole.escort, target: target),
        AppRoutes.roster,
      );
    });
  }

  for (final target in [AppRoutes.delay, AppRoutes.noShow]) {
    testWidgets('기사가 동승자 전용 $target 에 닿으면 운행 탭으로 돌려보낸다', (tester) async {
      expect(
        await landAfterGoing(tester, role: UserRole.driver, target: target),
        AppRoutes.home,
      );
    });
  }

  testWidgets('두 역할이 함께 쓰는 화면은 막지 않는다', (tester) async {
    expect(
      await landAfterGoing(
        tester,
        role: UserRole.driver,
        target: AppRoutes.offlineQueue,
      ),
      AppRoutes.offlineQueue,
    );
  });

  testWidgets('자기 역할의 전용 화면은 그대로 연다', (tester) async {
    expect(
      await landAfterGoing(
        tester,
        role: UserRole.escort,
        target: AppRoutes.delay,
      ),
      AppRoutes.delay,
    );
  });
}
