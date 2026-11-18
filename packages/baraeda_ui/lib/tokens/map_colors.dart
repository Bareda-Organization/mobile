import 'package:baraeda_ui/tokens/colors.dart';
import 'package:flutter/widgets.dart';

/// 지도 위 핀 · 노선 색 — 지도 어댑터는 `BuildContext` 없이 핀을 이미지로 굳히거나 SDK 오버레이를
/// 만들어 테마의 의미 색을 읽지 못한다. 그래서 정적 토큰으로 둔다.
///
/// [stopPin] · [stopPinSkipped] · [stopMarkerTint] · [mapPlaceholder] 는
/// 관계자 웹 지도 핀의 색과 같은 값이다 — 같은 정차지가 제품마다 다른 색이면
/// 기사와 관계자가 통화하며 같은 지점을 가리키기 어렵다.
abstract final class BaraedaMapColors {
  /// 정차지 핀(웹 `MARKER_COLOR.stop`).
  static const Color stopPin = Color(0xFF16A34A);

  /// 오늘 서지 않는 정차지 핀(웹 `SKIPPED_PIN_COLOR`).
  static const Color stopPinSkipped = Color(0xFF9CA3AF);

  /// 아이콘이 없는 승하차지 핀의 색 — 버스 핀(기본 초록)과 갈린다.
  static const Color stopMarkerTint = Color(0xFFE08A00);

  /// 지도 바탕이 준비되기 전 자리를 채우는 회색.
  static const Color mapPlaceholder = Color(0xFFE0E0E0);

  /// 승하차지 번호 핀의 둘레 · 내 승하차지 강조 색.
  static const Color numberPinAccent = BaraedaPalette.green600;

  /// 승하차지 번호 핀의 번호 · 둘레 잉크.
  static const Color numberPinInk = BaraedaPalette.stone700;

  /// 학부모 앱 노선(앞으로 갈 길).
  static const Color routeAhead = BaraedaPalette.green600;

  /// 학부모 앱 노선(지나온 길).
  static const Color routePassed = BaraedaPalette.stone400;
}
