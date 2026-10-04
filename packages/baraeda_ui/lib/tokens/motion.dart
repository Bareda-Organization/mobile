// 바래다 모션 — 짧고 단정하게. 바운스·오버슈트·스프링을 쓰지 않는다.
// `frontend/design-system/tokens/motion.css` 를 1:1 로 이식한 것.

import 'package:flutter/widgets.dart';

/// 지속 시간.
abstract final class BaraedaDuration {
  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 360);

  // ── 시안(`mkit/baraeda2-mobile.css`) 움직임 약속 — 누르는 것은 120ms 안에 반응한다 ──
  /// 누름 반응(단추 · 칩 · 행).
  static const Duration press = Duration(milliseconds: 120);

  /// 색 · 투명도 같은 일반 전환.
  static const Duration ui = Duration(milliseconds: 180);

  /// 하단 시트가 열리는 시간.
  static const Duration sheet = Duration(milliseconds: 240);

  /// 대화상자가 열리는 시간.
  static const Duration dialog = Duration(milliseconds: 200);

  /// 토스트가 뜨는 시간.
  static const Duration toast = Duration(milliseconds: 220);

  /// 시트 · 대화상자 뒤 어두운 막이 나타나는 시간.
  static const Duration scrim = Duration(milliseconds: 160);

  /// 불러오는 중 뼈대 한 번 깜빡이는 주기.
  static const Duration skeleton = Duration(milliseconds: 1400);

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

  /// 시안 `--ease-out` — 누름 · 대화상자 · 토스트.
  static const Curve easeOut = Cubic(0.23, 1, 0.32, 1);

  /// 시안 `--ease-drawer` — 시트 · 스위치 손잡이.
  static const Curve drawer = Cubic(0.32, 0.72, 0, 1);
}

/// 인터랙션 상수 — 애니메이션 곡선이 아니라 값 하나짜리 상수.
abstract final class BaraedaMotionValue {
  /// 프레스 시 스케일(시안 `:active{transform:scale(.97)}`).
  /// `Transform.scale(scale: BaraedaMotionValue.pressScale)`.
  static const double pressScale = 0.97;

  /// 누를 때 밝기(시안 `filter:brightness(.94)`) — 검정을 6% 덮어 어둡게 한다.
  static const double pressDim = 0.06;

  /// 호버 시 밝기 조정 비율 — `Color.withValues`/`HSLColor` 조합으로 8% 어둡게.
  static const double hoverTint = 0.08;
}
