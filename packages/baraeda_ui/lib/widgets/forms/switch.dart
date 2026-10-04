// 원본 `design-system/components/forms/Switch.jsx` 대응 + 시안 `.m-switch`.
//
// 시안: 손잡이 트랙 52×32 · 손잡이 26 · 줄 높이 44 이상(누름 면적). 꺼진 트랙은 배경과 3:1 이상이다.
// 누르는 동안 손잡이가 30 으로 늘어난다(움직임 줄이기가 켜지면 늘어나지 않는다).
import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/motion.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/word_wrap_text.dart';
import 'package:flutter/material.dart';

/// 온/오프 스위치 + 라벨 한 줄.
class BaraedaSwitch extends StatefulWidget {
  const new({
    required this.checked,
    required this.label,
    super.key,
    this.sublabel,
    this.onChanged,
    this.disabled = false,
  });

  final bool checked;
  final String label;
  final String? sublabel;
  final ValueChanged<bool>? onChanged;
  final bool disabled;

  @override
  State<BaraedaSwitch> createState() => _BaraedaSwitchState();
}

class _BaraedaSwitchState extends State<BaraedaSwitch> {
  bool _pressed = false;

  bool get _effectivelyDisabled => widget.disabled || widget.onChanged == null;

  void _setPressed(bool value) {
    if (_effectivelyDisabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Semantics(
      toggled: widget.checked,
      enabled: !_effectivelyDisabled,
      label: widget.label,
      child: Opacity(
        opacity: _effectivelyDisabled ? 0.42 : 1,
        child: InkWell(
          onTap: _effectivelyDisabled
              ? null
              : () => widget.onChanged!(!widget.checked),
          onTapDown: _effectivelyDisabled ? null : (_) => _setPressed(true),
          onTapUp: _effectivelyDisabled ? null : (_) => _setPressed(false),
          onTapCancel: _effectivelyDisabled ? null : () => _setPressed(false),
          hoverColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          focusColor: colors.focusRing.withValues(alpha: 0.32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: BaraedaSpacing.tap),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.label,
                        style: BaraedaTypography.body.copyWith(
                          color: colors.textPrimary,
                          fontWeight: BaraedaFontWeight.medium,
                          height: 1.3,
                        ),
                      ),
                      if (widget.sublabel != null)
                        WordWrapText(
                          widget.sublabel!,
                          style: BaraedaTypography.caption.copyWith(
                            color: colors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: BaraedaSpacing.space3),
                _SwitchTrack(
                  checked: widget.checked,
                  pressed: _pressed && !reduce,
                  animate: !reduce,
                  colors: colors,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchTrack extends StatelessWidget {
  const new({
    required this.checked,
    required this.pressed,
    required this.animate,
    required this.colors,
  });

  final bool checked;
  final bool pressed;
  final bool animate;
  final BaraedaColors colors;

  static const double _trackWidth = 52;
  static const double _trackHeight = 32;
  static const double _inset = 3;
  static const double _thumb = 26;
  static const double _thumbPressed = 30;

  @override
  Widget build(BuildContext context) {
    final duration = animate ? BaraedaDuration.ui : Duration.zero;
    final thumbWidth = pressed ? _thumbPressed : _thumb;
    // 켜짐에서 눌리면 손잡이가 오른쪽 끝에 붙은 채 왼쪽으로 늘어난다(시안 `translateX(16px)`).
    final left = checked ? _trackWidth - _inset - thumbWidth : _inset;

    return AnimatedContainer(
      duration: duration,
      curve: BaraedaCurve.easeOut,
      width: _trackWidth,
      height: _trackHeight,
      decoration: BoxDecoration(
        // 꺼짐 트랙은 배경과 3:1 이상 — 회색 면 + 손잡이로 켜짐을 가른다.
        color: checked ? colors.accentPrimary : colors.shapeIdle,
        borderRadius: BorderRadius.circular(_trackHeight / 2),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: duration,
            curve: BaraedaCurve.drawer,
            top: _inset,
            left: left,
            width: thumbWidth,
            height: _thumb,
            // 손잡이: 라이트는 늘 흰색, 다크 구역의 켜짐은 어두운 잉크(트랙이 밝은 앰버라서).
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: checked ? colors.textInverse : colors.mapControlSurface,
                borderRadius: BorderRadius.circular(_thumb / 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
