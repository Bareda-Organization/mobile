import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/features/auth/presentation/blocked_screen.dart';
import 'package:parent_app/features/auth/presentation/login_screen.dart';
import 'package:parent_app/features/auth/presentation/pending_approval_screen.dart';
import 'package:parent_app/features/auth/presentation/signup_screen.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';
import 'package:parent_app/features/live_map/presentation/live_map_screen.dart';
import 'package:parent_app/features/route/presentation/route_detail_screen.dart';
import 'package:parent_app/features/schedule/presentation/schedule_screen.dart';
import 'package:parent_app/features/settings/presentation/settings_screen.dart';

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
      // 밖의 화면에 못 들어간다(IMPLEMENTATION_PLAN.md §5.0 계정 상태
      // 게이트 표) — 대기 화면에 고정한다(UF-X-02).
      if (loggedIn &&
          (status == AccountStatus.pending ||
              status == AccountStatus.rejected)) {
        return location == AppRoutes.pendingApproval
            ? null
            : AppRoutes.pendingApproval;
      }

      if (!loggedIn && !onAuthScreen) return AppRoutes.login;
      if (loggedIn &&
          (onAuthScreen || location == AppRoutes.pendingApproval)) {
        return AppRoutes.home;
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
