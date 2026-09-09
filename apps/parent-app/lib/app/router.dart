import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/features/auth/presentation/login_screen.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';
import 'package:parent_app/features/live_map/presentation/live_map_screen.dart';
import 'package:parent_app/features/route/presentation/route_detail_screen.dart';
import 'package:parent_app/features/schedule/presentation/schedule_screen.dart';
import 'package:parent_app/features/settings/presentation/settings_screen.dart';

/// 화면 ↔ 라우트 대응은 IMPLEMENTATION_PLAN.md §3.1 6화면 그대로.
/// 지금은 자리표시 화면만 연결한다 — 화면 구현은 이번 범위가 아니다.
abstract final class AppRoutes {
  static const login = '/login';
  static const home = '/home';
  static const liveMap = '/live-map';
  static const routeDetail = '/route-detail';
  static const schedule = '/schedule';
  static const settings = '/settings';
}

/// `ref` 를 클로저로 들고 있다가 redirect 시점에 `read` 한다 — 로그인 여부에
/// 따라 진입 라우트가 갈리는 자리(§1.1)만 만들고, 실제 판정 로직(토큰 만료
/// 확인 등)은 `features/auth` 가 채운다.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.login,
    redirect: (context, state) {
      final role = ref.read<UserRole?>(currentUserRoleProvider);
      final loggedIn = role != null;
      final loggingIn = state.matchedLocation == AppRoutes.login;

      if (!loggedIn && !loggingIn) return AppRoutes.login;
      if (loggedIn && loggingIn) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.liveMap,
        builder: (context, state) => const LiveMapScreen(),
      ),
      GoRoute(
        path: AppRoutes.routeDetail,
        builder: (context, state) => const RouteDetailScreen(),
      ),
      GoRoute(
        path: AppRoutes.schedule,
        builder: (context, state) => const ScheduleScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});
