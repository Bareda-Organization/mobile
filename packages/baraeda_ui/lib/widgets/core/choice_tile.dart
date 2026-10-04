// 큰 선택 칸(라디오) — 여러 칸 중 하나를 고른다(시안 `.p-choice`). 꺼진 칸에는 이유 글이 반드시 붙는다.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/pressable.dart';
import 'package:flutter/material.dart';

/// 라디오 한 칸. 선택되면 초록 2px 테두리, 아니면 1px 테두리다.
///
/// [disabledReason] 이 있으면 꺼진 칸이다 — 누름에 반응하지 않고 보조 줄 자리에 이유가 보인다. 꺼진 글자색은
/// 새 값이 아니라 기존 보조 글자색이다(`Ruling 829`). 낭독은 제목에 이유를 이어 한 번에 읽는다.
class BaraedaChoiceTile extends StatelessWidget {
  const new({
    required this.title,
    super.key,
    this.subtitle,
    this.selected = false,
    this.disabledReason,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final bool selected;

  /// 이 칸을 고를 수 없는 이유. 있으면 꺼진 칸이다.
  final String? disabledReason;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final disabled = disabledReason != null;
    final radius = BorderRadius.circular(BaraedaRadius.control);
    final sub = disabledReason ?? subtitle;
    final spoken = disabled ? '$title, $disabledReason' : title;

    return BaraedaPressable(
      onTap: disabled ? null : onTap,
      borderRadius: radius,
      selected: selected,
      semanticLabel: spoken,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: disabled ? colors.disabledSurface : colors.surfaceCard,
          borderRadius: radius,
          border: Border.all(
            color: selected ? colors.accentPrimary : colors.borderControl,
            width: selected ? 2 : 1,
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: BaraedaSpacing.rowMinHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BaraedaSpacing.space3,
              vertical: BaraedaSpacing.space2,
            ),
            child: Row(
              children: [
                _Radio(selected: selected, disabled: disabled, colors: colors),
                const SizedBox(width: BaraedaSpacing.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: BaraedaTypography.body.copyWith(
                          color: disabled
                              ? colors.textSecondary
                              : colors.textPrimary,
                          fontWeight: BaraedaFontWeight.medium,
                        ),
                      ),
                      if (sub != null)
                        Text(
                          sub,
                          style: BaraedaTypography.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: BaraedaSpacing.space2),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const new({
    required this.selected,
    required this.disabled,
    required this.colors,
  });

  final bool selected;
  final bool disabled;
  final BaraedaColors colors;

  @override
  Widget build(BuildContext context) {
    final ring = disabled
        ? colors.borderControl
        : selected
        ? colors.accentPrimary
        : colors.borderControl;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ring, width: 2),
        ),
        child: SizedBox(
          width: 22,
          height: 22,
          child: selected
              ? Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.accentPrimary,
                    ),
                    child: const SizedBox(width: 10, height: 10),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
