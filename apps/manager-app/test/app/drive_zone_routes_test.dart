import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
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

/// L8(`Ruling 830`) — 매니저 앱은 라이트 기본이고 **운행 중 흐름의 화면만** 다크
/// 구역(`BaraedaDriveZone`)으로 감싼다: 운행 중 · 운행 종료 · 조회 전용 명단 ·
/// 노선 지도. 같은 앱의 다른 화면(홈 · 보고)은 라이트 그대로다.
void main() {
  Future<void> pumpAt(WidgetTester tester, String location) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
          currentAccountStatusProvider.overrideWith(
            (ref) => AccountStatus.active,
          ),
        ],
        child: const BaraedaManagerApp(),
      ),
    );
    await tester.pumpAndSettle();
    ProviderScope.containerOf(
      tester.element(find.byType(BaraedaManagerApp)),
    ).read(routerProvider).go(location);
    // 도착한 화면의 로딩 표시가 끝나지 않을 수 있어 pumpAndSettle 대신 시간을 정해 흘린다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  for (final route in [
    AppRoutes.driveMode,
    AppRoutes.runEnd,
    AppRoutes.rosterView,
    AppRoutes.routeMap,
  ]) {
    testWidgets('$route 는 다크 구역 안에서 그려진다', (tester) async {
      await pumpAt(tester, route);

      expect(find.byType(BaraedaDriveZone), findsOneWidget);
    });
  }

  for (final route in [AppRoutes.home, AppRoutes.report]) {
    testWidgets('$route 는 라이트 그대로다', (tester) async {
      await pumpAt(tester, route);

      expect(find.byType(BaraedaDriveZone), findsNothing);
    });
  }

  // 857 — 기사가 운전하는 동안 보는 화면에는 아래 탭 막대(알림 진입점)가 없다. 화면만 따로 그리면 라우트가 탭 틀
  // 안에 들어가 있어도 못 잡으므로 앱 전체를 열어 본다. 홈에는 탭 막대가 있다는 대조를 따로 둔다.
  testWidgets('/drive-mode 에는 아래 탭 막대가 없다', (tester) async {
    await pumpAt(tester, AppRoutes.driveMode);

    expect(find.byType(BaraedaTabBar), findsNothing);
  });

  testWidgets('/home 에는 아래 탭 막대가 있다 (위 시험의 대조)', (tester) async {
    await pumpAt(tester, AppRoutes.home);

    expect(find.byType(BaraedaTabBar), findsOneWidget);
  });
}
