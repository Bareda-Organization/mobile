// 원본 `design-system/components/core/StatusPill.jsx` 대응.
// readme.md: boarded=그린 · moving=앰버 · missed=레드 · idle=스톤 — 세 제품
// 전체에서 불변하는 매핑이며, 이 매핑은 `theme/baraeda_colors.dart`에만
// 있고 이 위젯은 그것을 그대로 읽기만 한다(새 매핑을 만들지 않는다).

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/baraeda_status.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:flutter/material.dart';

/// 운행 상태를 색 점 + 라벨로 보여주는 알약 배지.
///
/// `missed`는 한 화면에 한 번만 노출한다(prompt.md) — 이 위젯 자체는
/// 그 규칙을 강제하지 않으므로 호출부에서 지킨다.
class BaraedaStatusPill extends StatelessWidget {
  const new({
    required this.status,
    this.label,
    super.key,
    this.dot = true,
    this.icon,
  });

  final BaraedaStatus status;

  /// 예: `'승차 완료'`, `'이동 중'`.
  final String? label;

  /// 색 점 표시 여부. 아이콘을 쓰면 보통 점은 끈다.
  final bool dot;

  /// 점 대신 아이콘을 쓸 때 Lucide 이름.
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(status, context.colors);
    // 문구를 안 주면 상태 기본 라벨 — 디자인 시스템 StatusPill 의 규칙이다.
    final text = label ?? status.label;

    // 자식 Text 가 같은 문구를 이미 갖고 있어 자식을 가린다 — 안 그러면 두 번 읽힌다(F07-10).
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(BaraedaRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: BaraedaIcon(icon!, size: 13, color: palette.foreground),
              )
            else if (dot)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: palette.foreground,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            Text(
              text,
              style: BaraedaTypography.micro.copyWith(
                color: palette.foreground,
                fontWeight: BaraedaFontWeight.medium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPillPalette {
  const new({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}

_StatusPillPalette _paletteFor(BaraedaStatus status, BaraedaColors c) {
  switch (status) {
    case BaraedaStatus.boarded:
      return _StatusPillPalette(
        background: c.statusBoardedSoft,
        foreground: c.statusBoarded,
      );
    case BaraedaStatus.moving:
      return _StatusPillPalette(
        background: c.statusMovingSoft,
        foreground: c.statusMoving,
      );
    case BaraedaStatus.missed:
      return _StatusPillPalette(
        background: c.statusMissedSoft,
        foreground: c.statusMissed,
      );
    case BaraedaStatus.idle:
      return _StatusPillPalette(
        background: c.statusIdleSoft,
        foreground: c.statusIdle,
      );
  }
}
