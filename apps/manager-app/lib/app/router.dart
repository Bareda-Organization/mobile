import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/manager_shell.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/features/auth/presentation/blocked_screen.dart';
import 'package:manager_app/features/auth/presentation/login_screen.dart';
import 'package:manager_app/features/auth/presentation/password_change_screen.dart';
import 'package:manager_app/features/auth/presentation/pending_approval_screen.dart';
import 'package:manager_app/features/auth/presentation/signup_screen.dart';
import 'package:manager_app/features/delay/presentation/delay_screen.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_screen.dart';
import 'package:manager_app/features/emergency/presentation/emergency_screen.dart';
import 'package:manager_app/features/home/presentation/home_screen.dart';
import 'package:manager_app/features/home/presentation/me_screen.dart';
import 'package:manager_app/features/home/presentation/run_ready_screen.dart';
import 'package:manager_app/features/notifications/presentation/notifications_screen.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_screen.dart';
import 'package:manager_app/features/roster/presentation/no_show_screen.dart';
import 'package:manager_app/features/roster/presentation/roster_screen.dart';
import 'package:manager_app/features/route_map/presentation/route_map_screen.dart';
import 'package:manager_app/features/run_end/presentation/report_screen.dart';
import 'package:manager_app/features/run_end/presentation/run_end_screen.dart';

/// 기사 전용 화면 — 운행 준비 · 운행 중 · 운행 종료 · 조회 전용 명단(`canOperateRun`).
const Set<String> _driverOnlyRoutes = {
  AppRoutes.runReady,
  AppRoutes.driveMode,
  AppRoutes.runEnd,
  AppRoutes.rosterView,
};

/// 동승자 전용 화면 — 지연 알림(`canSendDelayNotification`) ·
/// 미승차 연락(`canDecideBoardingStatus`).
const Set<String> _escortOnlyRoutes = {AppRoutes.delay, AppRoutes.noShow};

/// 라우트 경로 상수는 [AppRoutes](`app_routes.dart`)를 본다 — 순환 참조
/// 방지 이유가 그 파일에 있다.
///
/// `ref` 를 클로저로 들고 있다가 redirect 시점에 `read` 한다 — 로그인 여부에
/// 따라 진입 라우트가 갈리는 자리(§1.1)만 만들고, 실제 판정 로직(토큰 만료
/// 확인 등)은 `features/auth` 가 채운다.
///
/// `refreshListenable` 에 [RouterRefreshNotifier] 를 물려 세션 중간의 계정
/// 게이트(목표 표 7항)도 다음 사용자 조작을 기다리지 않고 즉시 반영한다.
final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ref.watch(routerRefreshNotifierProvider);

  return GoRouter(
    initialLocation: AppRoutes.login,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final role = ref.read<UserRole?>(currentUserRoleProvider);
      final status = ref.read<AccountStatus?>(currentAccountStatusProvider);
      final loggedIn = role != null;
      final location = state.matchedLocation;
      final onAuthScreen =
          location == AppRoutes.login || location == AppRoutes.signup;

      // 차단 안내는 redirect 가 아니라 로그인 화면의 명시적 push 로만
      // 들어온다 — 여기서 벗어나게 하지 않는다(사용자가 로그아웃 안내를
      // 읽기 전에 다른 규칙이 화면을 넘겨버리면 안 된다).
      if (location == AppRoutes.blockedAccount) return null;

      // pending·rejected 는 토큰은 있으나(로그인 자체는 성공) 허용 4개
      // 밖의 화면에 못 들어간다(docs/archive/rounds/fe-phases-f2-f5.md §5.0 계정 상태
      // 게이트 표) — 대기 화면에 고정한다(UF-X-02).
      if (loggedIn &&
          (status == AccountStatus.pending ||
              status == AccountStatus.rejected)) {
        return location == AppRoutes.pendingApproval
            ? null
            : AppRoutes.pendingApproval;
      }

      // 임시 비밀번호 강제 변경(Ruling 540) — 서버가 그 밖의 API 를 막으므로 변경 화면에 고정한다.
      if (loggedIn && ref.read(mustChangePasswordProvider)) {
        return location == AppRoutes.passwordChange
            ? null
            : AppRoutes.passwordChange;
      }

      if (!loggedIn && !onAuthScreen) return AppRoutes.login;
      // 로그인 직후 첫 화면 — 동승자는 명단, 기사는 운행(시안 `home-driver` · `roster-escort`).
      if (loggedIn && (onAuthScreen || location == AppRoutes.pendingApproval)) {
        return role == UserRole.escort ? AppRoutes.roster : AppRoutes.home;
      }
      // 명단 탭은 동승자만 있다 — 기사가 닿으면 운행 탭으로(기사의 명단은 조회 전용 [rosterView]).
      if (loggedIn && role == UserRole.driver && location == AppRoutes.roster) {
        return AppRoutes.home;
      }
      // 역할 전용 화면(L5) — 다른 역할이 닿으면 서버 403 에만 기대지 않고 그 역할의 첫 화면으로 돌려보낸다.
      if (loggedIn) {
        final landing = role == UserRole.escort
            ? AppRoutes.roster
            : AppRoutes.home;
        if (role != UserRole.driver && _driverOnlyRoutes.contains(location)) {
          return landing;
        }
        if (role != UserRole.escort && _escortOnlyRoutes.contains(location)) {
          return landing;
        }
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: AppRoutes.pendingApproval,
        builder: (context, state) => const PendingApprovalScreen(),
      ),
      GoRoute(
        path: AppRoutes.blockedAccount,
        builder: (context, state) => const BlockedScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ManagerShell(navigationShell: navigationShell),
        branches: [
          // 브랜치 순서는 `ManagerShell.*Branch` 와 같다.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.roster,
                builder: (context, state) => const RosterScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const ManagerHomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.notifications,
                builder: (context, state) => const NotificationsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.me,
                builder: (context, state) => const MeScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.runReady,
        builder: (context, state) => const RunReadyScreen(),
      ),
      // 운행 중 화면은 항상 다크(`Ruling 830`) — 움직임 없는 구역으로 감싼다.
      GoRoute(
        path: AppRoutes.driveMode,
        builder: (context, state) =>
            const BaraedaDriveZone(child: DriveModeScreen()),
      ),
      GoRoute(
        path: AppRoutes.noShow,
        builder: (context, state) =>
            NoShowScreen(riderId: state.uri.queryParameters['rider']),
      ),
      GoRoute(
        path: AppRoutes.report,
        builder: (context, state) => const ReportScreen(),
      ),
      GoRoute(
        path: AppRoutes.reportGuardian,
        builder: (context, state) => const ReportScreen(guardianAbsent: true),
      ),
      // 운행 중 흐름에서 여는 조회 전용 명단 · 노선 지도 · 운행 종료도 다크 구역이다(`Ruling 830`).
      GoRoute(
        path: AppRoutes.rosterView,
        builder: (context, state) =>
            const BaraedaDriveZone(child: RosterScreen(readOnly: true)),
      ),
      GoRoute(
        path: AppRoutes.delay,
        builder: (context, state) => const DelayScreen(),
      ),
      GoRoute(
        path: AppRoutes.routeMap,
        builder: (context, state) =>
            const BaraedaDriveZone(child: RouteMapScreen()),
      ),
      GoRoute(
        path: AppRoutes.runEnd,
        builder: (context, state) =>
            const BaraedaDriveZone(child: RunEndScreen()),
      ),
      GoRoute(
        path: AppRoutes.emergency,
        builder: (context, state) => const EmergencyScreen(),
      ),
      GoRoute(
        path: AppRoutes.passwordChange,
        builder: (context, state) => const PasswordChangeScreen(),
      ),
      GoRoute(
        path: AppRoutes.offlineQueue,
        builder: (context, state) => const OfflineQueueScreen(),
      ),
    ],
  );
});
