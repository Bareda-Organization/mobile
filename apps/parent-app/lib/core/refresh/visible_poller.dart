import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 앱 안 주기 갱신 간격 — 홈(회차·일정 변경)과 탭 막대(알림 배지)가 함께 쓴다. 30초였던 것을 90초로 늘렸다(R46 D #7).
const Duration pollInterval = Duration(seconds: 90);

/// 주기 갱신 — 앱이 보이는 동안만 [interval] 마다 [onTick] 을 부른다.
///
/// 푸시 SDK 가 없어 앱 안 갱신이 유일한 통지 수단이지만(F05-06), 열려 있는 모든 앱이 짧은 간격으로
/// 서버를 치면 그 자체가 부하다(R46 D #7). 그래서 ①앱이 백그라운드(`paused`·`hidden`)이면 멈추고 ②다른 화면이
/// 위에 있으면([isCovered]) 그 틱을 건너뛰며 ③백그라운드에서 돌아오면 간격을 기다리지 않고 즉시 한 번 받는다.
/// 위치 실시간(WebSocket)은 이 갱신과 무관하다.
class VisiblePoller with WidgetsBindingObserver {
  new({required this.interval, required this.onTick, this.isCovered});

  final Duration interval;
  final VoidCallback onTick;

  /// `true` 이면 이번 틱을 건너뛴다 — 이 화면이 다른 화면에 가려졌다.
  final bool Function()? isCovered;

  Timer? _timer;
  bool _wasInBackground = false;

  /// 감시와 타이머를 시작한다.
  void start() {
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(interval, (_) {
      if (_wasInBackground || (isCovered?.call() ?? false)) return;
      onTick();
    });
  }

  /// 타이머와 감시를 끝낸다.
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _wasInBackground = true;
      case AppLifecycleState.resumed:
        if (_wasInBackground) {
          _wasInBackground = false;
          onTick();
        }
      case AppLifecycleState.inactive:
        break;
    }
  }
}

/// 지금 맨 위 화면의 경로가 [visiblePaths] 밖이면 `true` — 이 위젯이 다른 화면에 가려졌다.
/// 라우터가 없으면(위젯 시험 등) 가려지지 않은 것으로 본다.
bool isCoveredFrom(BuildContext context, Set<String> visiblePaths) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return false;
  // `uri` 는 `push` 한 화면을 반영하지 않는다 — 맨 위에 쌓인 화면은 마지막 match 의 경로다.
  return !visiblePaths.contains(
    router.routerDelegate.currentConfiguration.last.matchedLocation,
  );
}
