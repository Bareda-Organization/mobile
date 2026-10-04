// 누르는 면 하나 — 눌리는 동안 0.97 배로 줄고(120ms) 올림 · 눌림 색을 입힌다.
// 단추 · 알약 · 탭 · 지도 단추가 같은 반응을 내도록 한 곳에 둔다(시안 `:active`).
// 움직임 줄이기가 켜져 있으면 크기는 그대로 두고 색만 바꾼다.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/motion.dart';
import 'package:flutter/material.dart';

/// 눌림에 반응하는 영역. 꺼져 있으면([onTap] 이 null) 어떤 반응도 없다.
class BaraedaPressable extends StatefulWidget {
  const new({
    required this.child,
    required this.borderRadius,
    super.key,
    this.onTap,
    this.scale = BaraedaMotionValue.pressScale,
    this.semanticLabel,
    this.selected,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  /// 눌렸을 때 크기 배율.
  final double scale;

  /// 있으면 낭독 라벨을 이 문구로 한 번에 읽고 자식 글자는 가린다.
  final String? semanticLabel;

  /// 선택 상태를 낭독에 싣는다(탭 · 알약). null 이면 싣지 않는다.
  final bool? selected;

  @override
  State<BaraedaPressable> createState() => _BaraedaPressableState();
}

class _BaraedaPressableState extends State<BaraedaPressable> {
  bool _pressed = false;

  bool get _enabled => widget.onTap != null;

  void _set(bool value) {
    if (!_enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(BaraedaPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled && _pressed) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    Widget ink = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onTap,
        onTapDown: _enabled ? (_) => _set(true) : null,
        onTapUp: _enabled ? (_) => _set(false) : null,
        onTapCancel: _enabled ? () => _set(false) : null,
        borderRadius: widget.borderRadius,
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: _enabled
            ? Colors.black.withValues(alpha: BaraedaMotionValue.pressDim)
            : Colors.transparent,
        hoverColor: _enabled
            ? Colors.black.withValues(alpha: 0.04)
            : Colors.transparent,
        focusColor: colors.focusRing.withValues(alpha: 0.32),
        mouseCursor: _enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: widget.child,
      ),
    );

    if (widget.semanticLabel != null) {
      ink = Semantics(
        label: widget.semanticLabel,
        excludeSemantics: true,
        child: ink,
      );
    }

    return Semantics(
      container: true,
      button: true,
      enabled: _enabled,
      selected: widget.selected,
      child: AnimatedScale(
        scale: _pressed && !reduce ? widget.scale : 1,
        duration: BaraedaDuration.press,
        curve: BaraedaCurve.easeOut,
        child: ink,
      ),
    );
  }
}
