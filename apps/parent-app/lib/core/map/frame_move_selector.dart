import 'package:parent_app/core/map/marker_motion_controller.dart';

/// 이번 프레임에 실제로 `setPosition` 을 부를 마커 id 를 고른다.
///
/// 프레임(60Hz)마다 모든 마커에 네이티브 호출을 하면 정차지처럼 움직이지 않는 마커까지 초당 수십 번 호출돼
/// 배터리·발열만 쓴다(R46 D #11). 그래서 보간 중인 마커만 고른다. 보간이 끝난 **첫 프레임**은 마지막 자리에
/// 정확히 놓으려고 한 번 더 고르고, 그다음부터는 고르지 않는다.
class FrameMoveSelector {
  final Set<String> _movedLastFrame = {};

  /// [motions] 중 [now] 에 좌표를 옮겨야 하는 id.
  List<String> select(
    Map<String, MarkerMotionController> motions,
    DateTime now,
  ) {
    final ids = <String>[];
    final animatingNow = <String>{};
    for (final entry in motions.entries) {
      final animating = entry.value.isAnimating(now);
      if (animating) animatingNow.add(entry.key);
      if (animating || _movedLastFrame.contains(entry.key)) ids.add(entry.key);
    }
    _movedLastFrame
      ..clear()
      ..addAll(animatingNow);
    return ids;
  }
}
