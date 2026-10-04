// 다크 구역(운행 모드) — 기사가 하루 수십 번 보는 운행 화면 전용.
// 시안 `.m-dark`: 사양상 테마와 무관하게 항상 다크이고, 시트 · 대화상자 · 토스트도
// 움직임 없이 바로 뜬다(누름 반응만 남는다).

import 'package:baraeda_ui/theme/baraeda_theme.dart';
import 'package:flutter/material.dart';

/// 열리는 것(시트 · 대화상자 · 토스트)의 움직임 수준.
enum BaraedaOpenMotion {
  /// 이동 + 투명도 — 기본.
  full,

  /// 투명도만 — 움직임 줄이기(`MediaQuery.disableAnimations`).
  fadeOnly,

  /// 움직임 없이 바로 — 운행 중 다크 구역.
  none;

  /// [context] 에서 정해지는 수준. 다크 구역이 줄이기 설정보다 우선한다.
  static BaraedaOpenMotion of(BuildContext context) {
    if (BaraedaDriveZone.isIn(context)) return none;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return reduce ? fadeOnly : full;
  }
}

/// 운행 화면을 감싸는 다크 구역. 안쪽은 [BaraedaTheme.dark] 색을 쓰고,
/// 시트 · 대화상자 · 토스트는 움직임 없이 뜬다.
class BaraedaDriveZone extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  static final ThemeData _theme = BaraedaTheme.dark();

  /// [context] 가 다크 구역 안인가.
  static bool isIn(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_DriveZoneScope>() != null;

  /// 라우트 · 오버레이처럼 구역 밖에서 그려지는 것이 구역 안에서 호출됐을 때,
  /// 같은 구역(테마 + 움직임 없음)을 다시 씌운다.
  static Widget carry(BuildContext from, Widget child) {
    final theme = Theme.of(from);
    final wrapped = Theme(data: theme, child: child);
    return isIn(from) ? _DriveZoneScope(child: wrapped) : wrapped;
  }

  @override
  Widget build(BuildContext context) => _DriveZoneScope(
    child: Theme(data: _theme, child: child),
  );
}

class _DriveZoneScope extends InheritedWidget {
  const new({required super.child});

  @override
  bool updateShouldNotify(_DriveZoneScope oldWidget) => false;
}
