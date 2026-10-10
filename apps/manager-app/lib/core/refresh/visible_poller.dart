import 'dart:async';

import 'package:flutter/widgets.dart';

/// 주기 갱신 — 앱이 보이는 동안만 [interval] 마다 [onTick] 을 부른다(R52 M6).
///
/// 학부모 앱의 `core/refresh/visible_poller.dart` 와 같은 동작이다(frontend `Ruling 473`). ①앱이
/// 백그라운드(`paused`·`hidden`)이면 멈추고 ②백그라운드에서 돌아오면 간격을 기다리지 않고 즉시 한 번 부른다.
/// 공용 패키지로 옮길 후보지만 `packages/` 는 이 작업 소유가 아니라 매니저 앱 안에 둔다.
class VisiblePoller with WidgetsBindingObserver {
  new({required this.interval, required this.onTick});

  final Duration interval;
  final VoidCallback onTick;

  Timer? _timer;
  bool _wasInBackground = false;

  /// 감시와 타이머를 시작한다.
  void start() {
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(interval, (_) {
      if (_wasInBackground) return;
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
