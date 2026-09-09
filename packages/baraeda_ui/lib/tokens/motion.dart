// 바래다 모션 — 짧고 단정하게. 바운스·오버슈트·스프링을 쓰지 않는다.
// `frontend/design-system/tokens/motion.css` 를 1:1 로 이식한 것.

import 'package:flutter/widgets.dart';

/// 지속 시간.
abstract final class BaraedaDuration {
  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 360);

  /// 지도 카메라 이동·버스 마커 위치 보간 전용.
  static const Duration map = Duration(milliseconds: 600);

  /// `@media (prefers-reduced-motion: reduce)` 대응.
  /// `MediaQuery.disableAnimations` 가 켜져 있으면 CSS 원본과 같이 1ms 로 낮춘다.
  static Duration resolve(BuildContext context, Duration duration) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return disableAnimations ? const Duration(milliseconds: 1) : duration;
  }
}

/// 이징 곡선. CSS `cubic-bezier(x1,y1,x2,y2)` 는 Flutter `Cubic(x1,y1,x2,y2)` 와
/// 정의가 같아 값을 그대로 옮겼다.
abstract final class BaraedaCurve {
  static const Curve standard = Cubic(0.2, 0, 0.2, 1);
  static const Curve out = Cubic(0, 0, 0.2, 1);
  static const Curve emphasizedIn = Cubic(0.4, 0, 1, 1);
}

/// 인터랙션 상수 — 애니메이션 곡선이 아니라 값 하나짜리 상수.
abstract final class BaraedaMotionValue {
  /// 프레스 시 스케일. `Transform.scale(scale: BaraedaMotionValue.pressScale)`.
  static const double pressScale = 0.985;

  /// 호버 시 밝기 조정 비율 — `Color.withValues`/`HSLColor` 조합으로 8% 어둡게.
  static const double hoverTint = 0.08;
}
