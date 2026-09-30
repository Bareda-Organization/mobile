// 원본 `design-system/components/core/Button.jsx` 대응.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:flutter/material.dart';

/// 버튼 배색. primary=주요 행동 · secondary=보조 · soft=미스트 배경 ·
/// ghost=텍스트만 · danger=미탑승 처리·삭제 확정.
enum BaraedaButtonVariant { primary, secondary, soft, ghost, danger }

/// 버튼 높이. sm 36 · md 48 · lg 52(앱 주요 버튼은 lg).
/// md 는 터치 최소 `BaraedaSpacing.tapMin` 까지 키웠다(디자인 킷은 44, F07-10).
/// sm 은 조밀 배치용이라 보이는 크기만 36 이고, **누르는 영역은 48×48 이상**이다.
enum BaraedaButtonSize { sm, md, lg }

/// 바래다 기본 버튼.
///
/// 한 화면에 [BaraedaButtonVariant.primary]는 하나만 두고,
/// [BaraedaButtonVariant.danger]는 미탑승 처리·삭제 확정에만 쓴다.
/// [onPressed]가 null이면 비활성(opacity 0.42 · not-allowed 커서)이다.
class BaraedaButton extends StatelessWidget {
  const BaraedaButton({
    required this.label,
    super.key,
    this.onPressed,
    this.variant = BaraedaButtonVariant.primary,
    this.size = BaraedaButtonSize.md,
    this.icon,
    this.iconEnd,
    this.block = false,
  });

  /// 버튼 라벨. 항상 동사로 끝낸다(`readme.md` CONTENT FUNDAMENTALS).
  final String label;

  final VoidCallback? onPressed;
  final BaraedaButtonVariant variant;
  final BaraedaButtonSize size;

  /// 앞쪽 [BaraedaIcon] 이름.
  final String? icon;

  /// 뒤쪽 [BaraedaIcon] 이름.
  final String? iconEnd;

  /// 가로 100%.
  final bool block;

  bool get _disabled => onPressed == null;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = _paletteFor(variant, colors);
    final metrics = _metricsFor(size);
    final iconSize = size == BaraedaButtonSize.sm ? 16.0 : 18.0;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          BaraedaIcon(icon!, size: iconSize, color: palette.foreground),
          SizedBox(width: metrics.gap),
        ],
        Flexible(
          child: Text(
            label,
            style: metrics.textStyle.copyWith(color: palette.foreground),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (iconEnd != null) ...[
          SizedBox(width: metrics.gap),
          BaraedaIcon(iconEnd!, size: iconSize, color: palette.foreground),
        ],
      ],
    );

    // 버튼 역할과 활성 여부를 낭독기에 싣는다. 라벨은 자식 Text 가 읽는다(F07-10).
    final button = Semantics(
      button: true,
      enabled: !_disabled,
      child: Opacity(
        opacity: _disabled ? 0.42 : 1,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: _disabled ? null : onPressed,
            borderRadius: BorderRadius.circular(BaraedaRadius.control),
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            hoverColor: Colors.black.withValues(alpha: 0.06),
            highlightColor: Colors.black.withValues(alpha: 0.1),
            focusColor: colors.focusRing.withValues(alpha: 0.32),
            mouseCursor: _disabled
                ? SystemMouseCursors.forbidden
                : SystemMouseCursors.click,
            child: Ink(
              height: metrics.height,
              width: block ? double.infinity : null,
              padding: metrics.padding,
              decoration: BoxDecoration(
                color: palette.background,
                border: palette.border,
                borderRadius: BorderRadius.circular(BaraedaRadius.control),
              ),
              child: Center(child: content),
            ),
          ),
        ),
      ),
    );

    // 보이는 크기가 터치 최소보다 작으면(sm 36) 누르는 영역만 48 로 넓힌다(Ruling 404).
    // 영역이 레이아웃 박스 안이라 이웃 버튼과 겹치지 않는다. 낭독 노드는 위 Semantics 하나만 둔다.
    if (metrics.height >= BaraedaSpacing.tapMin) return button;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: _disabled ? null : onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: BaraedaSpacing.tapMin,
          minHeight: BaraedaSpacing.tapMin,
        ),
        child: Center(
          widthFactor: block ? null : 1,
          heightFactor: 1,
          child: button,
        ),
      ),
    );
  }
}

class _ButtonPalette {
  const _ButtonPalette({
    required this.background,
    required this.foreground,
    this.border,
  });

  final Color background;
  final Color foreground;
  final Border? border;
}

_ButtonPalette _paletteFor(BaraedaButtonVariant variant, BaraedaColors c) {
  switch (variant) {
    case BaraedaButtonVariant.primary:
      return _ButtonPalette(
        background: c.accentPrimary,
        foreground: c.textInverse,
      );
    case BaraedaButtonVariant.secondary:
      return _ButtonPalette(
        background: c.surfaceCard,
        foreground: c.textPrimary,
        border: Border.all(color: c.borderControl),
      );
    case BaraedaButtonVariant.soft:
      return _ButtonPalette(
        background: c.accentPrimarySoft,
        foreground: c.textBrand,
      );
    case BaraedaButtonVariant.ghost:
      return _ButtonPalette(
        background: Colors.transparent,
        foreground: c.textBrand,
      );
    case BaraedaButtonVariant.danger:
      return _ButtonPalette(
        background: c.statusMissed,
        foreground: c.textInverse,
      );
  }
}

class _ButtonMetrics {
  const _ButtonMetrics({
    required this.height,
    required this.padding,
    required this.gap,
    required this.textStyle,
  });

  final double height;
  final EdgeInsets padding;
  final double gap;
  final TextStyle textStyle;
}

_ButtonMetrics _metricsFor(BaraedaButtonSize size) {
  const weight = BaraedaFontWeight.medium;
  switch (size) {
    case BaraedaButtonSize.sm:
      return _ButtonMetrics(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        gap: 6,
        textStyle: BaraedaTypography.labelSm.copyWith(fontWeight: weight),
      );
    case BaraedaButtonSize.md:
      return _ButtonMetrics(
        height: BaraedaSpacing.tapMin,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        gap: 8,
        textStyle: BaraedaTypography.label.copyWith(fontWeight: weight),
      );
    case BaraedaButtonSize.lg:
      return _ButtonMetrics(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        gap: 8,
        textStyle: BaraedaTypography.body.copyWith(fontWeight: weight),
      );
  }
}
