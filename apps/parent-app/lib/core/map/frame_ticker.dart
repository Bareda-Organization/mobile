import 'dart:async';

/// 프레임마다 콜백을 부르는 아주 얇은 타이머 래퍼.
///
/// **판단 근거 — 왜 `Timer.periodic` 을 어댑터 안에 바로 두지 않고
/// 이 클래스로 뺐는가**: "화면이 사라질 때 타이머가 멈추는가"(누수
/// 여부)는 이 저장소에서 검사로 반드시 고정해야 하는 항목인데
/// (`COMMON-B2.md §2`), 지도 SDK 위젯 자체는 위젯 시험 환경(플랫폼
/// 채널 부재)에서 검증할 수 없다. `Timer` 는 순수 Dart 라 SDK 없이도
/// 단위 검사가 가능하므로, "타이머 시작·정지" 책임만 이 작은 클래스로
/// 분리해 그 부분만이라도 검사 가능하게 만든다.
class FrameTicker {
  FrameTicker({this.interval = const Duration(milliseconds: 16)});

  final Duration interval;
  Timer? _timer;

  /// 지금 도는 중인가 — dispose 검사가 "멈췄다"를 확인하는 근거.
  bool get isRunning => _timer != null;

  /// 이미 돌고 있으면 먼저 멈추고 새로 시작한다(중복 타이머 방지).
  void start(void Function() onTick) {
    stop();
    _timer = Timer.periodic(interval, (_) => onTick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
