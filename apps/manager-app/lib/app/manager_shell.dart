import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/manager_run_channel.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/notifications/presentation/notification_providers.dart';

/// 로그인 뒤 탭 화면들의 틀 — 아래 탭 막대(`BaraedaTabBar`)를 붙인다.
///
/// 기사는 `운행 · 알림 · 내 정보` 3칸, 동승자는 `명단 · 회차 · 알림 · 내 정보` 4칸이고 동승자의 첫 화면은 명단이다
/// (시안 `home-driver` · `home-escort`). 브랜치 번호는 `router.dart` 의
/// `StatefulShellRoute` 순서와 같다.
/// 운행 중 화면 · 운행 준비 · 비상 같은 화면은 이 틀 밖에서 위에 덮여 열린다 — 탭 막대가 없다.
///
/// 열려 있는 동안 [todayRunsRefreshInterval] 마다, 앱이 백그라운드에서 돌아올 때 오늘 회차 목록 · 알림을 다시
/// 받는다 — 확정은 서버 배치가 시각에 맞춰 바꾸므로 한 번 받은 목록은 곧 낡는다.
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

class _ManagerShellState extends ConsumerState<ManagerShell>
    with WidgetsBindingObserver {
  /// 오늘 회차 목록 · 알림을 [todayRunsRefreshInterval] 마다 다시 받는 타이머 — 쉘이 맡는다.
  /// 탭은 처음 갈 때 만들어지므로(`indexedStack` 지연 생성)
  /// 동승자가 첫 화면인 명단 탭에 머물면 홈은 존재하지 않는다.
  Timer? _refreshTimer;

  /// 쉘이 다른 화면에 덮여 있는 동안에도 선택 · 회차 목록의 변화를 보는 구독 — 위젯 구독(`ref.watch`)은 덮이면
  /// 멈추므로, 그 사이 선택이 바뀌고 끝난 회차를 쉘이 살아 있던 것으로 본 적이 없게 된다.
  final List<ProviderSubscription<Object?>> _selectionSubscriptions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final container = ProviderScope.containerOf(context, listen: false);
    void remember(Object? previous, Object? next) {
      _rememberLiveSelection(
        container.read(selectedRunIdProvider),
        container.read(todayRunsProvider).value ?? const [],
      );
    }

    _selectionSubscriptions
      ..add(container.listen(selectedRunIdProvider, remember))
      ..add(container.listen(todayRunsProvider, remember));
    _refreshTimer = Timer.periodic(
      todayRunsRefreshInterval,
      (_) => _reloadQuietly(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    for (final subscription in _selectionSubscriptions) {
      subscription.close();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _reloadQuietly();
    // 실시간 연결도 다시 붙게 한다 — REST 만 다시 읽으면 끊긴 소켓이 다음 재연결 타이머(최대 30초)를 기다린다.
    // 운행 화면이 열려 있지 않으면 듣는 컨트롤러가 없어 아무 일도 일어나지 않는다.
    ref.read(appResumedProvider.notifier).state++;
  }

  /// 회차 목록과 알림(배지)을 스피너 없이 다시 받는다 — 푸시 SDK 가 없어 앱 안 갱신이 유일한 통지 수단이다.
  void _reloadQuietly() {
    ref.invalidate(todayRunsProvider);
    unawaited(ref.read(notificationFeedProvider.notifier).refresh());
  }

  /// 끝나기 전에 쉘이 마지막으로 본 선택 회차 — 갈아타기는 "그 회차가 그 뒤 끝난 경우"에만 한다.
  String? _lastLiveSelectedRunId;

  /// 지금 선택이 살아 있는 회차면 기억하고, 끝난 다른 회차를 골랐으면 기억을 비운다.
  void _rememberLiveSelection(String? selected, List<ManagerRun> runs) {
    final selectedRun = runs.where((run) => run.runId == selected).firstOrNull;
    if (selectedRun == null) return;
    if (selectedRun.runStatus != RunStatus.finished) {
      _lastLiveSelectedRunId = selectedRun.runId;
    } else if (selectedRun.runId != _lastLiveSelectedRunId) {
      // 끝난 다른 회차를 골랐으면 기억한 살아 있던 회차는 낡은 값이다 — 비워 두지 않으면 나중에 그 회차를
      // 알림으로 고를 때 쉘이 다음 회차로 덮어 버린다.
      _lastLiveSelectedRunId = null;
    }
  }

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
    // 회차를 가리키면 그 회차로 갈아탄다 — 앞 회차가 끝난 뒤에도 명단 탭 · 지연 알림 · 예외 보고가 끝난 회차에
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
    _rememberLiveSelection(selected, runs);
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
