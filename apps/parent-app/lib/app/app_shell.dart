import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/network/network_status.dart';
import 'package:parent_app/core/refresh/visible_poller.dart';
import 'package:parent_app/features/notifications/presentation/notification_providers.dart';

/// 로그인 뒤 화면 아래의 탭 막대 — 학부모 `[홈]` `[일정]` `[알림]` `[설정]` · 학생 `[내 버스]` `[알림]` `[설정]` (R44 · R48).
///
/// `router.dart` 의 `StatefulShellRoute` 가 탭마다 화면 상태(스크롤 위치·받아 둔 목록)를
/// 따로 붙들어 두고,
/// 이 위젯은 그 위에 막대를 얹는다. 로그인·가입·대기·차단 화면과 지도·일정 같은 하위 화면은 탭 밖 경로라 막대가 없다.
///
/// 알림 탭 배지는 서버가 세는 안 읽은 수(§3.12 `unread_count`)다. 푸시 SDK 가 아직 없어 앱 안 갱신이 유일한
/// 통지 수단이므로(F05-06), 알림 탭을 열지 않아도 배지가 최신이 되도록
/// 여기서 [pollInterval] 마다·앱에 돌아올 때 목록을 다시 받는다.
class AppShell extends ConsumerStatefulWidget {
  const new({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  late final VisiblePoller _poller = VisiblePoller(
    interval: pollInterval,
    onTick: _refreshQuietly,
    // 탭 막대는 탭 화면에서만 보인다 — 지도·일정 같은 하위 화면이 위에 있으면 배지도 안 보이므로 쉰다.
    isCovered: () => isCoveredFrom(context, {
      AppRoutes.home,
      AppRoutes.schedule,
      AppRoutes.notifications,
      AppRoutes.settings,
    }),
  );

  @override
  void initState() {
    super.initState();
    _poller.start();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller.dispose();
    super.dispose();
  }

  /// 앱이 백그라운드에서 돌아왔다 — 끊겨 재연결 대기 중인 실시간 연결(위치 지도)을 다음 타이머(최대 30초)를
  /// 기다리지 않고 바로 다시 붙인다. 연결한 적 없거나 일부러 끊은 연결은 클라이언트가 건드리지 않는다(R46-FIXRT S-5).
  /// 알림 목록의 즉시 갱신은 [VisiblePoller] 가 맡는다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(webSocketClientProvider).reconnectNow();
    }
  }

  void _refreshQuietly() =>
      unawaited(ref.read(notificationFeedProvider.notifier).refresh());

  @override
  Widget build(BuildContext context) {
    // 서버에 못 닿다가 다시 닿았다 — 와이파이·데이터가 돌아온 것이다. 재연결 대기(최대 30초)가 끝나길 기다리지 않고 실시간
    // 연결을 바로 다시 붙인다. REST 성공이 이 앱에서 망 복귀의 유일한 신호다(R46-FIXCONN C-10).
    ref.listen(networkStatusProvider.select((status) => status.isOffline), (
      wasOffline,
      isOffline,
    ) {
      if (wasOffline ?? false) {
        if (!isOffline) ref.read(webSocketClientProvider).reconnectNow();
      }
    });
    final unread = ref.watch(
      notificationFeedProvider.select((feed) => feed.value?.unreadCount ?? 0),
    );
    // 일정을 편집하는 쪽(학부모)만 일정 탭이 있다 — 역할 문자열이 아니라 권한으로 가른다(§1.1).
    final hasScheduleTab =
        ref.watch(roleCapabilitiesProvider)?.canChangeBoardingLocation ?? true;
    final navigationShell = widget.navigationShell;
    final tabs = hasScheduleTab ? _parentTabs : _studentTabs;
    // 막대의 칸 순서와 라우터 가지(홈 · 일정 · 알림 · 설정) 순서가 다르다 — 학생은 일정 가지를 건너뛴다.
    final currentTab = tabs.indexWhere(
      (tab) => tab.branch == navigationShell.currentIndex,
    );

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BaraedaTabBar(
        currentIndex: currentTab < 0 ? 0 : currentTab,
        items: [
          for (final tab in tabs)
            BaraedaTabItem(
              icon: tab.icon,
              label: tab.label,
              badge: tab.branch == _notificationsBranch ? unread : 0,
            ),
        ],
        // 이미 보고 있는 탭을 다시 누르면 그 탭의 첫 화면으로.
        onChanged: (index) => navigationShell.goBranch(
          tabs[index].branch,
          initialLocation: tabs[index].branch == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

/// 라우터 가지 번호 — `router.dart` 의 `StatefulShellRoute` 가지 순서와 같다.
const _homeBranch = 0;
const _scheduleBranch = 1;
const _notificationsBranch = 2;
const _settingsBranch = 3;

class _Tab {
  const _Tab(this.branch, this.icon, this.label);

  final int branch;
  final String icon;
  final String label;
}

/// 학부모 `홈 · 일정 · 알림 · 설정` — 일정이 새 탭이다(`Ruling 826`).
const _parentTabs = [
  _Tab(_homeBranch, 'house', '홈'),
  _Tab(_scheduleBranch, 'calendar', '일정'),
  _Tab(_notificationsBranch, 'bell', '알림'),
  _Tab(_settingsBranch, 'settings', '설정'),
];

/// 학생 `내 버스 · 알림 · 설정` — 일정은 부모님 계정에서 관리한다.
const _studentTabs = [
  _Tab(_homeBranch, 'house', '내 버스'),
  _Tab(_notificationsBranch, 'bell', '알림'),
  _Tab(_settingsBranch, 'settings', '설정'),
];
