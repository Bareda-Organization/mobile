// 원본 `design-system/components/core/Button.jsx` 대응 + 시안 `.m-btn`(`mkit/baraeda2-mobile.css`).

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/motion.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:flutter/material.dart';

/// 버튼 배색. primary=주요 행동 · secondary=보조 · soft=미스트 배경 ·
/// ghost=밑줄 글자 · danger=위험 면(미탑승 처리·삭제 확정) ·
/// dangerOutline=위험 선(흰 면 + 위험 글자 — 되돌릴 수 없지만 주 행동은 아닐 때).
enum BaraedaButtonVariant {
  primary,
  secondary,
  soft,
  ghost,
  danger,
  dangerOutline,
}

/// 버튼 높이. sm 44 · md 48 · xl 64(운행 중 큰 주 버튼).
/// lg 는 예전 이름이다 — 시안에 52 가 없어 md 와 같은 48 로 둔다.
enum BaraedaButtonSize { sm, md, lg, xl }

/// 바래다 기본 버튼.
///
/// 한 화면에 [BaraedaButtonVariant.primary]는 하나만 두고,
/// [BaraedaButtonVariant.danger]는 미탑승 처리·삭제 확정에만 쓴다.
///
/// - [onPressed]가 null이면 꺼짐이다 — 면 `disabledSurface` · 글자 `disabledText`,
///   누름·올림에 **아무 반응이 없다**(시안 C3). 왜 꺼졌는지는 [disabledReason] 으로
///   단추 아래에 적는다("새 비밀번호를 입력하면 눌러요").
/// - [name] 은 단추 안 긴 이름이다. 이름만 `…` 로 줄고 [label](동사)은 늘 보인다
///   (시안 M5 `새솔초 정문 도착 처리`).
/// - 누르는 동안 0.97 배로 줄고 6% 어두워진다(120ms). 움직임 줄이기가 켜져 있으면
///   크기는 그대로 두고 색만 바뀐다.
class BaraedaButton extends StatefulWidget {
  const new({
    required this.label,
    super.key,
    this.onPressed,
    this.variant = BaraedaButtonVariant.primary,
    this.size = BaraedaButtonSize.md,
    this.icon,
    this.iconEnd,
    this.block = false,
    this.name,
    this.disabledReason,
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

  /// 가로 100%. false 면 내용 폭(Column stretch 처럼 부모가 폭을 강제하는 자리는 그 폭).
  final bool block;

  /// 라벨 앞에 붙는 긴 이름(승하차지·학원 이름). 폭이 모자라면 이름만 `…` 로 줄고 [label] 은 남는다.
  final String? name;

  /// 꺼져 있을 때 단추 아래에 적는 이유 한 줄. 켜지면 사라진다. 낭독에는 힌트로 실린다.
  final String? disabledReason;

  @override
  State<BaraedaButton> createState() => _BaraedaButtonState();
}

class _BaraedaButtonState extends State<BaraedaButton> {
  bool _pressed = false;

  bool get _disabled => widget.onPressed == null;

  void _setPressed(bool value) {
    if (_disabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(BaraedaButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 누르는 도중 꺼지면 눌림 표시를 풀어 준다.
    if (_disabled && _pressed) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = _paletteFor(widget.variant, colors, disabled: _disabled);
    final metrics = _metricsFor(widget.size);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final pressedNow = _pressed && !_disabled;
    // 눌린 면 — 흰 면(보조)·투명(고스트)은 어둡게 덮을 바탕이 없어 올림 색만 쓴다.
    final background = pressedNow && palette.background.a == 1
        ? Color.alphaBlend(
            Colors.black.withValues(alpha: BaraedaMotionValue.pressDim),
            palette.background,
          )
        : palette.background;

    final textStyle = metrics.textStyle.copyWith(
      color: palette.foreground,
      decoration: widget.variant == BaraedaButtonVariant.ghost && !_disabled
          ? TextDecoration.underline
          : null,
      decorationColor: palette.foreground,
      decorationThickness: 1,
    );

    final named = widget.name != null;
    final spoken = named ? '${widget.name} ${widget.label}' : widget.label;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          BaraedaIcon(
            widget.icon!,
            size: metrics.iconSize,
            color: palette.foreground,
          ),
          SizedBox(width: metrics.gap),
        ],
        if (named) ...[
          // 이름은 한 줄 · 모자라면 `…`. 동사는 아래에서 줄지 않는다.
          Flexible(
            child: Text(
              widget.name!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ),
          SizedBox(width: metrics.gap),
          Text(widget.label, maxLines: 1, softWrap: false, style: textStyle),
        ] else
          Flexible(
            child: Text(
              widget.label,
              style: textStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (widget.iconEnd != null) ...[
          SizedBox(width: metrics.gap),
          BaraedaIcon(
            widget.iconEnd!,
            size: metrics.iconSize,
            color: palette.foreground,
          ),
        ],
      ],
    );

    // 이름 + 동사는 따로 읽히지 않게 한 문장으로 싣는다.
    final content = named
        ? Semantics(label: spoken, excludeSemantics: true, child: row)
        : row;
    final radius = BorderRadius.circular(BaraedaRadius.control);
    final button = AnimatedScale(
      scale: pressedNow && !reduceMotion ? BaraedaMotionValue.pressScale : 1,
      duration: BaraedaDuration.press,
      curve: BaraedaCurve.easeOut,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _disabled ? null : widget.onPressed,
          onTapDown: _disabled ? null : (_) => _setPressed(true),
          onTapUp: _disabled ? null : (_) => _setPressed(false),
          onTapCancel: _disabled ? null : () => _setPressed(false),
          borderRadius: radius,
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          // 꺼진 단추는 올림 · 눌림 색이 없다 — 켜진 것처럼 보이지 않게(C3).
          hoverColor: _disabled
              ? Colors.transparent
              : Colors.black.withValues(alpha: 0.06),
          highlightColor: Colors.transparent,
          focusColor: colors.focusRing.withValues(alpha: 0.32),
          mouseCursor: _disabled
              ? SystemMouseCursors.forbidden
              : SystemMouseCursors.click,
          child: Ink(
            height: metrics.height,
            width: widget.block ? double.infinity : null,
            padding: metrics.padding,
            decoration: BoxDecoration(
              color: background,
              border: palette.border,
              borderRadius: radius,
            ),
            // block 이 아니면 내용 폭 — 디자인 킷 `inline-flex`(R43).
            // 부모가 폭 상한만 줘도 늘어나지 않는다.
            // 가장 짧은 라벨도 누르는 면은 44×44 이상이다(시안 `--tap`).
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: BaraedaSpacing.tap),
              child: Center(
                widthFactor: widget.block ? null : 1,
                child: content,
              ),
            ),
          ),
        ),
      ),
    );

    final reason = _disabled ? widget.disabledReason : null;

    // 낭독은 바깥 한 노드가 맡는다 — 역할 · 꺼짐 · 이유(힌트). 누르기 · 초점 동작은 안쪽
    // [InkWell] 이 같은 노드에 합쳐 싣는다. 이름 + 동사는 한 번에 이어 읽는다.
    return Semantics(
      container: true,
      button: true,
      enabled: !_disabled,
      hint: reason,
      child: reason == null
          ? button
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: widget.block
                  ? CrossAxisAlignment.stretch
                  : CrossAxisAlignment.center,
              children: [
                button,
                // 이유는 위 힌트가 이미 읽는다.
                ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      reason,
                      textAlign: TextAlign.center,
                      style: BaraedaTypography.caption.copyWith(
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ButtonPalette {
  const new({required this.background, required this.foreground, this.border});

  final Color background;
  final Color foreground;
  final Border? border;
}

_ButtonPalette _paletteFor(
  BaraedaButtonVariant variant,
  BaraedaColors c, {
  required bool disabled,
}) {
  // 꺼짐은 변형과 상관없이 같은 면 · 글자 · 테두리 없음 — 시안 `.m-btn[disabled]`.
  if (disabled) {
    return _ButtonPalette(
      background: c.disabledSurface,
      foreground: c.disabledText,
    );
  }
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
        background: c.dangerSolid,
        foreground: c.onDangerSolid,
      );
    case BaraedaButtonVariant.dangerOutline:
      return _ButtonPalette(
        background: c.surfaceCard,
        foreground: c.statusMissed,
        border: Border.all(color: c.borderControl),
      );
  }
}

class _ButtonMetrics {
  const new({
    required this.height,
    required this.padding,
    required this.gap,
    required this.iconSize,
    required this.textStyle,
  });

  final double height;
  final EdgeInsets padding;
  final double gap;
  final double iconSize;
  final TextStyle textStyle;
}

_ButtonMetrics _metricsFor(BaraedaButtonSize size) {
  const medium = BaraedaFontWeight.medium;
  switch (size) {
    case BaraedaButtonSize.sm:
      return _ButtonMetrics(
        height: BaraedaSpacing.controlSm,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        gap: 8,
        iconSize: 20,
        textStyle: BaraedaTypography.caption.copyWith(
          fontWeight: medium,
          height: 1.2,
        ),
      );
    case BaraedaButtonSize.md:
    case BaraedaButtonSize.lg:
      return _ButtonMetrics(
        height: BaraedaSpacing.controlMd,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        gap: 8,
        iconSize: 20,
        textStyle: BaraedaTypography.body.copyWith(
          fontWeight: medium,
          height: 1.2,
        ),
      );
    case BaraedaButtonSize.xl:
      return _ButtonMetrics(
        height: BaraedaSpacing.controlXl,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        gap: 10,
        iconSize: 24,
        textStyle: BaraedaTypography.body.copyWith(
          fontSize: BaraedaFontSize.title,
          fontWeight: BaraedaFontWeight.bold,
          height: 1.2,
        ),
      );
  }
}
