import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/features/notifications/presentation/notification_providers.dart';

/// 로그인 뒤 화면 아래의 탭 막대 — `[홈]` `[알림]` `[설정]` (학부모·학생 공통, R44).
///
/// `router.dart` 의 `StatefulShellRoute` 가 탭마다 화면 상태(스크롤 위치·받아 둔 목록)를
/// 따로 붙들어 두고,
/// 이 위젯은 그 위에 막대를 얹는다. 로그인·가입·대기·차단 화면과 지도·일정 같은 하위 화면은 탭 밖 경로라 막대가 없다.
///
/// 알림 탭 배지는 서버가 세는 안 읽은 수(§3.12 `unread_count`)다. 푸시 SDK 가 아직 없어 앱 안 갱신이 유일한
/// 통지 수단이므로(F05-06), 알림 탭을 열지 않아도 배지가 최신이 되도록 여기서 30초마다·앱에 돌아올 때 목록을 다시 받는다.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  static const _autoRefreshInterval = Duration(seconds: 30);

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_autoRefreshInterval, (_) => _refreshQuietly());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshQuietly();
  }

  void _refreshQuietly() =>
      unawaited(ref.read(notificationFeedProvider.notifier).refresh());

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final unread = ref.watch(
      notificationFeedProvider.select((feed) => feed.value?.unreadCount ?? 0),
    );
    final navigationShell = widget.navigationShell;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.borderChrome)),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            height: BaraedaSpacing.tabBarHeight,
            backgroundColor: colors.surfaceChrome,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            indicatorColor: colors.navActiveBg,
            iconTheme: WidgetStateProperty.resolveWith(
              (states) => IconThemeData(
                size: 24,
                color: states.contains(WidgetState.selected)
                    ? colors.navActiveText
                    : colors.navText,
              ),
            ),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => BaraedaTypography.labelSm.copyWith(
                fontWeight: states.contains(WidgetState.selected)
                    ? BaraedaFontWeight.bold
                    : BaraedaFontWeight.regular,
                color: states.contains(WidgetState.selected)
                    ? colors.navActiveText
                    : colors.navText,
              ),
            ),
          ),
          child: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            // 이미 보고 있는 탭을 다시 누르면 그 탭의 첫 화면으로.
            onDestinationSelected: (index) => navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            ),
            destinations: [
              const NavigationDestination(
                icon: BaraedaIcon('house'),
                label: '홈',
              ),
              NavigationDestination(
                icon: _UnreadBadge(
                  count: unread,
                  child: const BaraedaIcon('bell'),
                ),
                label: '알림',
              ),
              const NavigationDestination(
                icon: BaraedaIcon('settings'),
                label: '설정',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 알림 아이콘 위 건수 배지 — 99건이 넘으면 `99+`. 낭독기에는 건수를 문장으로 싣고 숫자 글자는 가린다.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: count > 0 ? '안 읽은 알림 $count건' : null,
      excludeSemantics: count > 0,
      child: Badge(
        isLabelVisible: count > 0,
        backgroundColor: colors.statusMissed,
        textColor: colors.textInverse,
        label: Text(count > 99 ? '99+' : '$count'),
        child: child,
      ),
    );
  }
}
