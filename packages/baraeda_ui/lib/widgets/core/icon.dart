// 원본 `design-system/components/core/Icon.jsx`은 Lucide SVG를 CSS mask로
// 그려 currentColor를 따른다. 브랜드 아이콘 자산은 제공되지 않았고
// (readme.md ICONOGRAPHY), Flutter에는 URL SVG를 mask로 그리는 표준 수단이 없다.
// 그래서 Lucide 이름(kebab-case)을 키로 두고 Flutter 내장 Material 아이콘
// 폰트로 대체한다 — 새 패키지를 추가하지 않고, 이름 체계는 원본과 그대로
// 맞춰 둬서 실제 Lucide 자산이 오면 이 매핑 테이블 하나만 바꾸면 된다.
//
// ⚠ Material 아이콘은 대체로 채워진(filled) 글리프라 Lucide의 2px stroke
// 느낌과 다르다 — 시각적 근사이지 1:1 대체가 아니다.

import 'package:flutter/material.dart';

/// Lucide 아이콘 이름 → Flutter [IconData]. `readme.md` ICONOGRAPHY의
/// "자주 쓰는 이름" 전부와, `Icon.prompt.md`·`IconButton.prompt.md` 예시에
/// 나오는 이름을 포함한다.
const Map<String, IconData> _kBaraedaIconGlyphs = {
  'bus': Icons.directions_bus,
  'map-pin': Icons.location_on,
  'route': Icons.alt_route,
  'navigation': Icons.navigation,
  'bell': Icons.notifications,
  'bell-off': Icons.notifications_off,
  'users-round': Icons.groups,
  'user-round': Icons.person,
  'clock': Icons.access_time,
  'phone': Icons.call,
  'check': Icons.check,
  'x': Icons.close,
  'chevron-right': Icons.chevron_right,
  'chevron-left': Icons.chevron_left,
  'chevron-down': Icons.expand_more,
  'search': Icons.search,
  'settings': Icons.settings,
  'plus': Icons.add,
  'pencil': Icons.edit,
  'trash-2': Icons.delete,
  'triangle-alert': Icons.warning_amber,
  'circle-check': Icons.check_circle,
  'circle-alert': Icons.error,
  'calendar': Icons.calendar_today,
  'list': Icons.list,
  'layout-dashboard': Icons.dashboard,
  'log-out': Icons.logout,
  'house': Icons.home,
};

/// Lucide 아이콘 래퍼 — 바래다의 모든 아이콘은 이걸 통해 쓴다.
///
/// 원본은 `<Icon name="bus" />`처럼 부모의 `color`(currentColor)를 상속하지만,
/// Flutter에는 그 상속 개념이 없어 [color]를 명시하지 않으면 앰비언트
/// [IconTheme]을 따른다 — CSS `currentColor`와 같은 효과다.
///
/// ```dart
/// const BaraedaIcon('bus', size: 24)
/// BaraedaIcon('triangle-alert', color: context.colors.statusMissed)
/// ```
class BaraedaIcon extends StatelessWidget {
  const BaraedaIcon(
    this.name, {
    super.key,
    this.size = 20,
    this.color,
    this.semanticLabel,
  });

  /// Lucide 아이콘 이름(kebab-case). 예: `'bus'`, `'map-pin'`.
  final String name;

  /// px. 앱 기본 20, 탭바 24, 인라인 16.
  final double size;

  /// null이면 [IconTheme]을 따른다(currentColor와 동등).
  final Color? color;

  /// 아이콘만 단독으로 의미를 전달할 때만 채운다(헤더 액션·전화 버튼 등).
  /// 텍스트와 항상 함께 쓰는 장식용 아이콘은 비워 둬 스크린 리더가 건너뛰게 한다.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final glyph = _kBaraedaIconGlyphs[name];
    assert(glyph != null, 'BaraedaIcon: 알 수 없는 아이콘 이름 "$name"');
    return Icon(
      glyph ?? Icons.help_outline,
      size: size,
      color: color,
      semanticLabel: semanticLabel,
    );
  }
}
