// 걸러 보기 · 자녀 전환 같은 누르는 알약 — 겉은 칩이고 누름 면적은 높이 44(시안 `.m-pill`).

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/pressable.dart';
import 'package:flutter/material.dart';

/// 누르는 알약. 선택되면 초록 면 + 흰 글자, 아니면 흰 면 + 테두리.
/// 이름이 길면 이 칸만 줄어들며 `…` 로 잘린다(이름 전체는 다음 화면).
class BaraedaFilterPill extends StatelessWidget {
  const new({
    required this.label,
    super.key,
    this.selected = false,
    this.onTap,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// 글자 앞에 둘 것(아바타 · 아이콘).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = selected ? colors.textInverse : colors.textPrimary;
    const radius = BorderRadius.all(Radius.circular(BaraedaRadius.pill));

    return BaraedaPressable(
      onTap: onTap,
      borderRadius: radius,
      selected: selected,
      semanticLabel: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? colors.accentPrimary : colors.surfaceCard,
          borderRadius: radius,
          border: selected ? null : Border.all(color: colors.borderControl),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: BaraedaSpacing.tap),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: BaraedaSpacing.space2),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BaraedaTypography.caption.copyWith(
                      color: foreground,
                      fontWeight: BaraedaFontWeight.medium,
                      height: 1,
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
