import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/notifications/presentation/notification_providers.dart';

/// 로그인 뒤 탭 화면들의 틀 — 아래 탭 막대(`BaraedaTabBar`)를 붙인다.
///
/// 기사는 `운행 · 알림 · 내 정보` 3칸, 동승자는 `명단 · 회차 · 알림 · 내 정보` 4칸이고 동승자의 첫 화면은 명단이다
/// (시안 `home-driver` · `home-escort`). 브랜치 번호는 `router.dart` 의
/// `StatefulShellRoute` 순서와 같다.
/// 운행 중 화면 · 운행 준비 · 비상 같은 화면은 이 틀 밖에서 위에 덮여 열린다 — 탭 막대가 없다.
class ManagerShell extends ConsumerWidget {
  const new({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  /// `StatefulShellRoute` 브랜치 번호.
  static const rosterBranch = 0;
  static const homeBranch = 1;
  static const notificationsBranch = 2;
  static const meBranch = 3;

  /// 역할이 보는 탭의 브랜치 번호 순서.
  static List<int> branchesOf(UserRole? role) => switch (role) {
    UserRole.escort => const [
      rosterBranch,
      homeBranch,
      notificationsBranch,
      meBranch,
    ],
    _ => const [homeBranch, notificationsBranch, meBranch],
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserRoleProvider);
    final unread = ref.watch(
      notificationFeedProvider.select((feed) => feed.value?.unreadCount ?? 0),
    );
    final branches = branchesOf(role);
    final current = branches.indexOf(navigationShell.currentIndex);

    // 회차를 아직 고르지 않았거나 고른 회차가 오늘 목록에서 사라졌으면 자동 선택을 담는다(진행 중 > 확정된 가장
    // 이른) — 동승자의 첫 화면 명단이 홈을 거치지 않고도 회차를 안다. 이미 끝난 회차는 그대로 둔다: 방금 끝낸 운행의
    // 종료 화면이 다음 회차로 바뀌어 보이면 안 된다.
    final focus = ref.watch(focusRunProvider);
    final selected = ref.watch(selectedRunIdProvider);
    final runs = ref.watch(todayRunsProvider).value ?? const [];
    if (focus != null &&
        (selected == null || !runs.any((run) => run.runId == selected))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(selectedRunIdProvider.notifier).state = focus.runId;
      });
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BaraedaTabBar(
        items: [
          for (final branch in branches)
            switch (branch) {
              rosterBranch => const BaraedaTabItem(icon: 'list', label: '명단'),
              homeBranch => BaraedaTabItem(
                icon: 'bus',
                label: role == UserRole.escort ? '회차' : '운행',
              ),
              notificationsBranch => BaraedaTabItem(
                icon: 'bell',
                label: '알림',
                badge: unread,
              ),
              _ => const BaraedaTabItem(icon: 'user-round', label: '내 정보'),
            },
        ],
        currentIndex: current < 0 ? 0 : current,
        onChanged: (index) => navigationShell.goBranch(
          branches[index],
          initialLocation: branches[index] == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
