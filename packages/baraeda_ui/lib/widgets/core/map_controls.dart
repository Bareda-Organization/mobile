// 지도 위에 얹는 단추 · 이름표 — 밝은 지도 면 위라 다크 구역에서도 흰 면 + 잉크 글자로 고정이다
// (시안 `.m-map__fab` · `.p-mapbtn` · `.m-map__tag`).

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:baraeda_ui/widgets/core/pressable.dart';
import 'package:flutter/material.dart';

/// 지도 단추. [label] 이 없으면 48×48 정사각(아이콘만), 있으면 높이 44 알약.
/// 아이콘만일 때는 [semanticLabel] 이 필수다.
class BaraedaMapButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.semanticLabel,
    super.key,
    this.label,
    this.onPressed,
  });

  /// Lucide 아이콘 이름.
  final String icon;
  final String semanticLabel;
  final String? label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pill = label != null;
    final radius = BorderRadius.circular(
      pill ? BaraedaRadius.pill : BaraedaRadius.control,
    );

    return BaraedaPressable(
      onTap: onPressed,
      borderRadius: radius,
      scale: 0.94,
      semanticLabel: pill ? '$semanticLabel $label' : semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.mapControlSurface,
          borderRadius: radius,
          border: Border.all(color: colors.mapControlLine),
          boxShadow: BaraedaShadows.smLight,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: pill ? 0 : 48,
            minHeight: pill ? BaraedaSpacing.tap : 48,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: pill ? 14 : 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                BaraedaIcon(icon, color: colors.onMapControl),
                if (pill) ...[
                  const SizedBox(width: BaraedaSpacing.space2),
                  Text(
                    label!,
                    style: BaraedaTypography.caption.copyWith(
                      color: colors.onMapControl,
                      fontWeight: BaraedaFontWeight.medium,
                      height: 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 지도 위 이름표 — `● 12:14:08 기준`. [stale] 이면 앰버 면으로 "오래된 위치" 를 알린다.
class BaraedaMapTag extends StatelessWidget {
  const new({
    required this.label,
    super.key,
    this.live = true,
    this.stale = false,
  });

  final String label;

  /// 앞에 초록 점(실시간).
  final bool live;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final background = stale
        ? colors.statusMovingSoft
        : colors.mapControlSurface;
    final foreground = stale ? colors.statusMoving : colors.onMapControl;
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(BaraedaRadius.pill),
          border: Border.all(
            color: stale ? colors.shapeMoving : colors.mapControlLine,
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (live && !stale) ...[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.shapeBoarded,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox(width: 8, height: 8),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BaraedaTypography.micro.copyWith(
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
