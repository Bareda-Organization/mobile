import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/features/auth/presentation/login_screen.dart';
import 'package:manager_app/features/delay/presentation/delay_screen.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_screen.dart';
import 'package:manager_app/features/emergency/presentation/emergency_screen.dart';
import 'package:manager_app/features/home/presentation/home_screen.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_screen.dart';
import 'package:manager_app/features/roster/presentation/roster_screen.dart';
import 'package:manager_app/features/route_map/presentation/route_map_screen.dart';
import 'package:manager_app/features/run_end/presentation/run_end_screen.dart';

/// 화면 ↔ 라우트 대응은 IMPLEMENTATION_PLAN.md §3.2 7화면 + 킷 부재 2종 그대로.
/// 지금은 자리표시 화면만 연결한다 — 화면 구현은 이번 범위가 아니다.
abstract final class AppRoutes {
  static const login = '/login';
  static const home = '/home';
  static const driveMode = '/drive-mode';
  static const roster = '/roster';
  static const delay = '/delay';
  static const routeMap = '/route-map';
  static const runEnd = '/run-end';
  static const emergency = '/emergency';
  static const offlineQueue = '/offline-queue';
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
        builder: (context, state) => const ManagerHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.driveMode,
        builder: (context, state) => const DriveModeScreen(),
      ),
      GoRoute(
        path: AppRoutes.roster,
        builder: (context, state) => const RosterScreen(),
      ),
      GoRoute(
        path: AppRoutes.delay,
        builder: (context, state) => const DelayScreen(),
      ),
      GoRoute(
        path: AppRoutes.routeMap,
        builder: (context, state) => const RouteMapScreen(),
      ),
      GoRoute(
        path: AppRoutes.runEnd,
        builder: (context, state) => const RunEndScreen(),
      ),
      GoRoute(
        path: AppRoutes.emergency,
        builder: (context, state) => const EmergencyScreen(),
      ),
      GoRoute(
        path: AppRoutes.offlineQueue,
        builder: (context, state) => const OfflineQueueScreen(),
      ),
    ],
  );
});
