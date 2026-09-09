// 바래다 모서리·테두리·그림자 — 그림자는 항상 그린 기반, 낮고 넓게.
// `frontend/design-system/tokens/shape.css` 를 1:1 로 이식한 것.

import 'package:flutter/widgets.dart';

/// 모서리 반경.
abstract final class BaraedaRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xl2 = 28;

  /// 완전한 알약 모양 — CSS `999px` 를 그대로 옮기되 Flutter 는 `BorderRadius.circular`
  /// 로 반지름이 요소 절반을 넘으면 자동으로 최대 원형이 되므로 큰 값을 그대로 써도 안전하다.
  static const double pill = 999;

  static const double card = 16;
  static const double control = 12;
  static const double sheet = 24;
}

/// 테두리 두께.
abstract final class BaraedaBorderWidth {
  static const double hairline = 1;
  static const double strong = 2;
}

/// 그림자 — 라이트/다크 별로 분리한다. 전부 그린 잉크(`rgba(18,33,28,…)`) 기반이고,
/// 다크에서만 검정 기반(`rgba(0,0,0,…)`)으로 바뀐다 (`--shadow-sheet` 는 다크에서도
/// 재정의되지 않아 그린 기반을 그대로 쓴다 — CSS 원본과 동일하게 옮겼다).
abstract final class BaraedaShadows {
  // ── 라이트 ──────────────────────────────────────────
  static const List<BoxShadow> smLight = [
    BoxShadow(color: Color(0x0F12211C), offset: Offset(0, 1), blurRadius: 2),
  ];

  static const List<BoxShadow> cardLight = [
    BoxShadow(color: Color(0x0F12211C), offset: Offset(0, 1), blurRadius: 3),
    BoxShadow(
      color: Color(0x1A12211C),
      offset: Offset(0, 6),
      blurRadius: 16,
      spreadRadius: -8,
    ),
  ];

  static const List<BoxShadow> raisedLight = [
    BoxShadow(color: Color(0x1412211C), offset: Offset(0, 2), blurRadius: 6),
    BoxShadow(
      color: Color(0x2912211C),
      offset: Offset(0, 16),
      blurRadius: 32,
      spreadRadius: -16,
    ),
  ];

  /// 지도 위 바텀시트 — 위로(상단 방향) 뻗는 유일한 그림자.
  static const List<BoxShadow> sheet = [
    BoxShadow(
      color: Color(0x3812211C),
      offset: Offset(0, -8),
      blurRadius: 32,
      spreadRadius: -12,
    ),
  ];

  // ── 다크 ────────────────────────────────────────────
  static const List<BoxShadow> smDark = [
    BoxShadow(color: Color(0x52000000), offset: Offset(0, 1), blurRadius: 2),
  ];

  static const List<BoxShadow> cardDark = [
    BoxShadow(color: Color(0x57000000), offset: Offset(0, 1), blurRadius: 3),
    BoxShadow(
      color: Color(0x70000000),
      offset: Offset(0, 6),
      blurRadius: 16,
      spreadRadius: -8,
    ),
  ];

  static const List<BoxShadow> raisedDark = [
    BoxShadow(color: Color(0x61000000), offset: Offset(0, 2), blurRadius: 6),
    BoxShadow(
      color: Color(0x8C000000),
      offset: Offset(0, 16),
      blurRadius: 32,
      spreadRadius: -16,
    ),
  ];

  /// `--focus-shadow: 0 0 0 3px
  /// color-mix(in oklch, var(--focus-ring) 32%, transparent)`.
  /// `color-mix(color, transparent)` 는 투명과의 혼합이라 알파를 곱하는 것과 같아
  /// `ringColor.withValues(alpha: .32)` 로 그대로 옮길 수 있다. 테마의 focus-ring 색은
  /// 라이트/다크가 다르므로(초록 500 / 앰버 400) 값을 인자로 받는다.
  static List<BoxShadow> focusRing(Color ringColor) => [
    BoxShadow(color: ringColor.withValues(alpha: 0.32), spreadRadius: 3),
  ];
}

/// `--shadow-inset: inset 0 1px 0 rgba(255,255,255,.5)`.
///
/// Flutter `BoxShadow` 에는 CSS 의 `inset` 에 대응하는 옵션이 없다 — 바깥으로만
/// 퍼진다. 값은 보존해 두되(향후 `CustomPainter` 또는 `ShaderMask` 로 구현할 때 참조),
/// `BoxDecoration.boxShadow` 에 바로 꽂아 쓸 수는 없다는 점을 이름으로도 드러낸다.
class BaraedaInsetShadowSpec {
  const BaraedaInsetShadowSpec({
    required this.color,
    required this.offset,
    required this.blurRadius,
  });

  final Color color;
  final Offset offset;
  final double blurRadius;

  static const light = BaraedaInsetShadowSpec(
    color: Color(0x80FFFFFF),
    offset: Offset(0, 1),
    blurRadius: 0,
  );

  static const dark = BaraedaInsetShadowSpec(
    color: Color(0x0FFFFFFF),
    offset: Offset(0, 1),
    blurRadius: 0,
  );
}
