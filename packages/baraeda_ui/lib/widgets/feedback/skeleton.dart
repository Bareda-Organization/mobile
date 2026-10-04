// 불러오는 중 뼈대 — 최종 화면과 같은 모양의 회색 면. 반짝임은 투명도만이고
// 움직임 줄이기가 켜지면 멈춘다(시안 `.m-skel` · kit "불러오는 중 · 뼈대").

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/motion.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:flutter/material.dart';

/// 뼈대 한 조각. [width] 를 비우면 부모 폭을 다 쓴다.
///
/// 1.4초 주기로 투명도 1 → 0.5 → 1 만 바뀐다(크기 · 위치는 그대로).
/// `MediaQuery.disableAnimations` 가 켜져 있으면 애니메이션을 아예 돌리지 않는다.
class BaraedaSkeleton extends StatefulWidget {
  const new({super.key, this.width, this.height = 16, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  State<BaraedaSkeleton> createState() => _BaraedaSkeletonState();
}

class _BaraedaSkeletonState extends State<BaraedaSkeleton>
    with SingleTickerProviderStateMixin {
  // 반주기(1 → 0.5)가 700ms 라 왕복이 시안의 1.4초 주기다.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: BaraedaDuration.skeleton ~/ 2,
  );
  late final Animation<double> _pulse = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.colors.statusIdleSoft;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) =>
            Opacity(opacity: 1 - 0.5 * _pulse.value, child: child),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}

/// 목록 한 줄 뼈대 — 목록 칸(`BaraedaListRow`)과 같은 높이(56 이상) · 같은 구성
/// (앞 칸 · 두 줄 글자 · 뒤 칩)이라 불러온 뒤 자리가 바뀌지 않는다.
class BaraedaSkeletonRow extends StatelessWidget {
  const new({super.key, this.showTrailing = true});

  /// 뒤쪽 칩 뼈대를 둘지.
  final bool showTrailing;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: BaraedaSpacing.rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const BaraedaSkeleton(width: 36, height: 36, radius: 8),
            const SizedBox(width: BaraedaSpacing.space3),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FractionallySizedBox(
                    widthFactor: 0.6,
                    child: BaraedaSkeleton(),
                  ),
                  SizedBox(height: 6),
                  FractionallySizedBox(
                    widthFactor: 0.4,
                    child: BaraedaSkeleton(height: 13),
                  ),
                ],
              ),
            ),
            if (showTrailing) ...[
              const SizedBox(width: BaraedaSpacing.space3),
              const BaraedaSkeleton(
                width: 64,
                height: 26,
                radius: BaraedaRadius.pill,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 목록 뼈대 — 카드 하나 안에 [count] 줄. 낭독은 "불러오는 중" 한 번만 읽는다.
class BaraedaSkeletonList extends StatelessWidget {
  const new({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      container: true,
      label: '불러오는 중',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          borderRadius: BorderRadius.circular(BaraedaRadius.card),
          boxShadow: Theme.of(context).brightness == Brightness.dark
              ? BaraedaShadows.cardDark
              : BaraedaShadows.cardLight,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(BaraedaRadius.card),
          child: Column(
            children: [
              for (var i = 0; i < count; i++) ...[
                if (i > 0) Divider(height: 1, color: colors.borderSubtle),
                const BaraedaSkeletonRow(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
