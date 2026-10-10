import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/notifications/presentation/notification_providers.dart';

/// 로그인 뒤 탭 화면들의 틀 — 아래 탭 막대(`BaraedaTabBar`)를 붙인다.
///
/// 기사는 `운행 · 알림 · 내 정보` 3칸, 동승자는 `명단 · 회차 · 알림 · 내 정보` 4칸이고 동승자의 첫 화면은 명단이다
/// (시안 `home-driver` · `home-escort`). 브랜치 번호는 `router.dart` 의
/// `StatefulShellRoute` 순서와 같다.
/// 운행 중 화면 · 운행 준비 · 비상 같은 화면은 이 틀 밖에서 위에 덮여 열린다 — 탭 막대가 없다.
class ManagerShell extends ConsumerStatefulWidget {
  const new({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<ManagerShell> createState() => _ManagerShellState();

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
}

class _ManagerShellState extends ConsumerState<ManagerShell> {
  /// 끝나기 전에 쉘이 마지막으로 본 선택 회차 — 갈아타기는 "그 회차가 그 뒤 끝난 경우"에만 한다.
  String? _lastLiveSelectedRunId;

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    final role = ref.watch(currentUserRoleProvider);
    final unread = ref.watch(
      notificationFeedProvider.select((feed) => feed.value?.unreadCount ?? 0),
    );
    final branches = ManagerShell.branchesOf(role);
    final current = branches.indexOf(navigationShell.currentIndex);

    // 회차를 아직 고르지 않았거나 고른 회차가 오늘 목록에서 사라졌으면 자동 선택을 담는다(진행 중 > 확정된 가장
    // 이른) — 동승자의 첫 화면 명단이 홈을 거치지 않고도 회차를 안다. 고른 회차가 **끝났고** 큰 카드(focus)가 다른
    // 회차를 가리키면 그 회차로 갈아탄다(R52 H1) — 앞 회차가 끝난 뒤에도 명단 탭 · 지연 알림 · 예외 보고가 끝난 회차에
    // 머물지 않게 한다. 갈아타기는 쉘이 맨 위 화면일 때만 한다: 운행 종료 · 보고 화면이 위에 떠 있는 동안
    // 방금 끝낸 운행의 화면이 다음 회차로 바뀌어 보이면 안 된다(그 화면을 닫으면 그때 갈아탄다).
    // 이미 끝난 회차를 사용자가 일부러 고른 경우(끝난 회차를 가리키는 알림을 누른 때)는 덮지 않는다 — 갈아타기는
    // 쉘이 끝나기 전에 본 선택이 그 뒤 끝난 경우에만 한다.
    final focus = ref.watch(focusRunProvider);
    final selected = ref.watch(selectedRunIdProvider);
    final runs = ref.watch(todayRunsProvider).value ?? const [];
    final selectedRun = runs.where((run) => run.runId == selected).firstOrNull;
    final isTop = ModalRoute.of(context)?.isCurrent ?? true;
    final selectedFinished = selectedRun?.runStatus == RunStatus.finished;
    if (selectedRun != null && !selectedFinished) {
      _lastLiveSelectedRunId = selectedRun.runId;
    }
    if (focus != null &&
        (selectedRun == null ||
            (isTop &&
                selectedFinished &&
                selectedRun.runId == _lastLiveSelectedRunId &&
                selectedRun.runId != focus.runId))) {
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
              ManagerShell.rosterBranch => const BaraedaTabItem(
                icon: 'list',
                label: '명단',
              ),
              ManagerShell.homeBranch => BaraedaTabItem(
                icon: 'bus',
                label: role == UserRole.escort ? '회차' : '운행',
              ),
              ManagerShell.notificationsBranch => BaraedaTabItem(
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
