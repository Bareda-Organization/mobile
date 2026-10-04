// 토스트 — 방금 한 일이 됐다는 짧은 확인. 220ms ease-out 로 떠오르고 가벼운 성공 햅틱을
// 한 번 울린다(시안 C7 · kit "완료 토스트"). 운행 중 다크 구역에서는 움직임 없이 바로 뜬다.

import 'dart:async';

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/theme/baraeda_drive_zone.dart';
import 'package:baraeda_ui/tokens/motion.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 토스트 한 장. 보통은 [showBaraedaToast] 로 띄운다.
class BaraedaToast extends StatefulWidget {
  const new({
    required this.message,
    required this.motion,
    super.key,
    this.actionLabel,
    this.onAction,
  });

  final String message;

  /// 움직임 수준 — 보이는 쪽(오버레이)이 호출한 자리의 [BaraedaOpenMotion] 을 넘긴다.
  final BaraedaOpenMotion motion;

  /// 되돌리기 같은 한 가지 행동. 둘 다 있어야 단추가 보인다.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<BaraedaToast> createState() => BaraedaToastState();
}

class BaraedaToastState extends State<BaraedaToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: BaraedaDuration.toast,
    reverseDuration: BaraedaDuration.scrim,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: BaraedaCurve.easeOut,
  );

  @override
  void initState() {
    super.initState();
    if (widget.motion == BaraedaOpenMotion.none) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  /// 사라진다 — 움직임이 없으면 바로, 아니면 짧게 흐려지며.
  Future<void> dismiss() async {
    if (widget.motion == BaraedaOpenMotion.none) return;
    await _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasAction = widget.actionLabel != null && widget.onAction != null;
    final text = BaraedaTypography.body.copyWith(
      color: colors.onInkSurface,
      fontWeight: BaraedaFontWeight.medium,
      height: 1.4,
    );

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.inkSurface,
        borderRadius: BorderRadius.circular(BaraedaRadius.control),
        boxShadow: Theme.of(context).brightness == Brightness.dark
            ? BaraedaShadows.raisedDark
            : BaraedaShadows.raisedLight,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: ExcludeSemantics(
                  child: Text(widget.message, style: text),
                ),
              ),
              if (hasAction)
                Semantics(
                  button: true,
                  label: widget.actionLabel,
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: widget.onAction,
                    borderRadius: BorderRadius.circular(BaraedaRadius.sm),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: BaraedaSpacing.tap,
                        minWidth: BaraedaSpacing.tap,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            widget.actionLabel!,
                            style: text.copyWith(
                              color: colors.inkAction,
                              fontWeight: BaraedaFontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final body = Semantics(
      container: true,
      liveRegion: true,
      label: widget.message,
      child: card,
    );

    return switch (widget.motion) {
      BaraedaOpenMotion.none => body,
      BaraedaOpenMotion.fadeOnly => FadeTransition(
        opacity: _curve,
        child: body,
      ),
      // 시안 `m-rise-s` — 12px 아래에서 투명하게 올라온다.
      BaraedaOpenMotion.full => FadeTransition(
        opacity: _curve,
        child: AnimatedBuilder(
          animation: _curve,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, 12 * (1 - _curve.value)),
            child: child,
          ),
          child: body,
        ),
      ),
    };
  }
}

OverlayEntry? _current;
Timer? _timer;

/// 화면 아래(탭 막대 위)에 토스트를 띄운다. 이미 떠 있던 토스트는 바로 걷어낸다.
///
/// 가벼운 성공 햅틱을 한 번 울리고, [duration] 뒤에 저절로 사라진다.
/// [aboveTabBar] 가 false 면 탭 막대가 없는 화면(운행 중)용 낮은 자리에 뜬다. 화면 아래에 큰 단추 줄이 있어
/// 그 위로 띄워야 하면 [bottomOffset](안전 영역 위 기준 거리)을 준다.
void showBaraedaToast(
  BuildContext context, {
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
  bool aboveTabBar = true,
  double? bottomOffset,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final motion = BaraedaOpenMotion.of(context);
  // 오버레이가 다시 그려질 때 호출 위치가 이미 비활성일 수 있어 지금 읽어 둔다.
  final zone = BaraedaDriveZone.capture(context);
  final bottom =
      MediaQuery.paddingOf(context).bottom +
      (bottomOffset ??
          (aboveTabBar
              ? BaraedaSpacing.tabBarHeight + BaraedaSpacing.space4
              : 16));
  final key = GlobalKey<BaraedaToastState>();

  _timer?.cancel();
  _current?.remove();

  late final OverlayEntry entry;
  Future<void> close() async {
    _timer?.cancel();
    await key.currentState?.dismiss();
    if (_current == entry) {
      entry.remove();
      _current = null;
    }
  }

  entry = OverlayEntry(
    builder: (_) => Positioned(
      left: BaraedaSpacing.gutterMobile,
      right: BaraedaSpacing.gutterMobile,
      bottom: bottom,
      child: BaraedaDriveZone.carry(
        zone,
        Material(
          type: MaterialType.transparency,
          child: BaraedaToast(
            key: key,
            message: message,
            motion: motion,
            actionLabel: actionLabel,
            onAction: onAction == null
                ? null
                : () {
                    onAction();
                    unawaited(close());
                  },
          ),
        ),
      ),
    ),
  );
  _current = entry;
  overlay.insert(entry);
  unawaited(HapticFeedback.lightImpact());
  _timer = Timer(duration, () => unawaited(close()));
}
