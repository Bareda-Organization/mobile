import 'package:baraeda_app/map/marker_motion_controller.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

/// 보간 중인 마커를 프레임마다 옮기는 틱 — 계산 자체는 `MarkerMotionController`(순수)에 맡기고, 이 클래스는
/// "언제 부를지"만 담당한다. `MapSurfaceOptions.smoothMarkerMotion` 이 켜졌을 때만 쓴다.
class NaverMarkerDriver {
  /// 틱은 `vsync` 로 만들고, `markersById` 에 올라가 있는 마커를 옮긴다.
  new(this._vsync, this._markersById);

  final TickerProvider _vsync;
  final Map<String, NMarker> _markersById;

  /// 마커 id 별 보간 상태.
  final MarkerMotionController motion = MarkerMotionController();

  /// 화면 프레임마다 도는 틱 — 보간 중인 마커가 하나라도 있을 때만 켠다(프레임마다 `setPosition` 을 부르는
  /// 비용은 실제로 움직이는 마커가 있을 때만 낸다). 앱이 백그라운드(paused)면 프레임이 없어 네이티브 호출도 0이다.
  late final Ticker _ticker = _vsync.createTicker(
    (_) => (_debugTick ?? _onFrameTick)(),
  );

  /// 시험이 틱 콜백을 바꿔 끼우는 자리 — [debugStart] 만 쓴다.
  VoidCallback? _debugTick;

  /// 보간 중인 마커가 하나라도 있으면 타이머를 돌리고, 없으면 멈춘다.
  void syncTicker(DateTime now) {
    if (motion.isAnimating(now)) {
      if (!_ticker.isActive) _ticker.start();
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onFrameTick() {
    final now = DateTime.now();
    // 보간 중인(움직이는) 마커만 옮긴다 — 정차지 마커는 네이티브 호출 0.
    for (final id in motion.idsToMove(now)) {
      final marker = _markersById[id];
      final position = motion.positionAt(id, now);
      if (marker != null && position != null) {
        marker.setPosition(NLatLng(position.lat, position.lng));
      }
    }
    syncTicker(now);
  }

  /// 시험 전용 — 같은 틱을 [onTick] 으로 바꿔 끼워 돌린다.
  void debugStart(VoidCallback onTick) {
    _debugTick = onTick;
    if (!_ticker.isActive) _ticker.start();
  }

  /// 틱을 해제한다 — 안 하면 화면을 벗어난 뒤에도 프레임마다 `setPosition` 을 계속 부른다.
  void dispose() => _ticker.dispose();
}
