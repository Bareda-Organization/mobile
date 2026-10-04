// 원본 `design-system/components/core/StatusPill.jsx` 대응 + 시안 `.m-chip`.
// readme.md: boarded=그린 · moving=앰버 · missed=레드 · idle=스톤 — 세 제품
// 전체에서 불변하는 매핑이며, 이 매핑은 `theme/baraeda_colors.dart`에만
// 있고 이 위젯은 그것을 그대로 읽기만 한다(새 매핑을 만들지 않는다).

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/baraeda_status.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:baraeda_ui/widgets/core/status_mark.dart';
import 'package:flutter/material.dart';

/// 칩 크기. md=높이 26 · 글자 13(기본) · lg=높이 32 · 글자 14(머리 상태).
enum BaraedaStatusPillSize { md, lg }

/// 운행 상태를 모양 + 라벨로 보여주는 알약 배지.
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
    this.size = BaraedaStatusPillSize.md,
  });

  final BaraedaStatus status;

  /// 예: `'승차 완료'`, `'이동 중'`.
  final String? label;

  /// 상태 모양(■ ▶ ● ○ ▲) 표시 여부. 아이콘을 쓰면 보통 끈다.
  final bool dot;

  /// 모양 대신 아이콘을 쓸 때 Lucide 이름.
  final String? icon;

  final BaraedaStatusPillSize size;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(status, context.colors);
    // 문구를 안 주면 상태 기본 라벨 — 디자인 시스템 StatusPill 의 규칙이다.
    final text = label ?? status.label;
    final large = size == BaraedaStatusPillSize.lg;

    // 자식 Text 가 같은 문구를 이미 갖고 있어 자식을 가린다 — 안 그러면 두 번 읽힌다(F07-10).
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(BaraedaRadius.pill),
          // 이동 중 · 대기 칩은 모양 색 1px 안쪽 테두리를 두른다(시안 `--k-*`).
          border: palette.stroke == null
              ? null
              : Border.all(color: palette.stroke!),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: large ? 32 : 26),
          child: Padding(
            padding: large
                ? const EdgeInsets.fromLTRB(11, 4, 12, 4)
                : const EdgeInsets.fromLTRB(9, 2, 10, 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  BaraedaIcon(icon!, size: 13, color: palette.foreground),
                  const SizedBox(width: 6),
                ] else if (dot) ...[
                  BaraedaStatusMark(shape: status.shape, color: palette.shape),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (large
                                ? BaraedaTypography.caption
                                : BaraedaTypography.micro)
                            .copyWith(
                              color: palette.foreground,
                              fontWeight: BaraedaFontWeight.bold,
                              height: 1.2,
                            ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPillPalette {
  const new({
    required this.background,
    required this.foreground,
    required this.shape,
    this.stroke,
  });

  final Color background;
  final Color foreground;
  final Color shape;
  final Color? stroke;
}

_StatusPillPalette _paletteFor(BaraedaStatus status, BaraedaColors c) {
  switch (status) {
    case BaraedaStatus.boarded:
      return _StatusPillPalette(
        background: c.statusBoardedSoft,
        foreground: c.statusBoarded,
        shape: c.shapeBoarded,
      );
    case BaraedaStatus.moving:
      return _StatusPillPalette(
        background: c.statusMovingSoft,
        foreground: c.statusMoving,
        shape: c.shapeMoving,
        stroke: c.shapeMoving,
      );
    case BaraedaStatus.missed:
      return _StatusPillPalette(
        background: c.statusMissedSoft,
        foreground: c.statusMissed,
        shape: c.dangerSolid,
      );
    case BaraedaStatus.idle:
      return _StatusPillPalette(
        background: c.statusIdleSoft,
        foreground: c.statusIdle,
        shape: c.shapeIdle,
      );
    case BaraedaStatus.waiting:
      return _StatusPillPalette(
        background: c.statusWaitSoft,
        foreground: c.statusWait,
        shape: c.shapeWait,
        stroke: c.shapeWait,
      );
  }
}
