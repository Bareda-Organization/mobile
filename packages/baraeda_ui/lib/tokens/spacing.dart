// 바래다 여백 — 4px 배수.
// `frontend/design-system/tokens/space.css` 를 1:1 로 이식한 것.

/// 여백 스케일과 레이아웃 치수. 값 단위는 논리 픽셀.
abstract final class BaraedaSpacing {
  static const double space0 = 0;
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;
  static const double space10 = 40;
  static const double space12 = 48;
  static const double space16 = 64;
  static const double space20 = 80;

  /// 앱 화면 좌우 여백.
  static const double gutterMobile = 20;

  /// 관계자 웹 좌우 여백 (매니저 앱이 데스크톱 폭으로 뜰 때 참조).
  static const double gutterDesktop = 32;

  static const double cardPadding = 20;
  static const double cardGap = 12;
  static const double sectionGap = 32;

  /// 최소 터치 영역 — 버튼 등 탭 가능한 요소의 하한.
  static const double tapMin = 48;

  static const double headerHeight = 56;
  static const double tabBarHeight = 64;
  static const double sideNavWidth = 248;
  static const double contentMaxWidth = 1160;
}
