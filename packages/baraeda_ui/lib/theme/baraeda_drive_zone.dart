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

  /// 라우트 · 오버레이를 **열기 전에** 호출한 자리의 테마와 구역 여부를 지금 한 번 읽어 둔다.
  ///
  /// 읽는 것을 경로 빌더 안으로 미루면 안 된다 — 호출한 화면이 닫히는 중에도 열려 있던 경로는
  /// 다시 그려지는데, 그때 호출 위치는 이미 비활성이라 `Theme.of` 가 예외를 던진다
  /// (2026-10-04 학부모 앱 일정 화면 `[나가기]` 시험에서 확인).
  static ({ThemeData theme, bool inZone}) capture(BuildContext from) =>
      (theme: Theme.of(from), inZone: isIn(from));

  /// [capture] 로 읽어 둔 값을 구역 밖에서 그려지는 경로 · 오버레이에 다시 씌운다 —
  /// 같은 테마 + (구역 안이었다면) 움직임 없음.
  static Widget carry(({ThemeData theme, bool inZone}) zone, Widget child) {
    final wrapped = Theme(data: zone.theme, child: child);
    return zone.inZone ? _DriveZoneScope(child: wrapped) : wrapped;
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
