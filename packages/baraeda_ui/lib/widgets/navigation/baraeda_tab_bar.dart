// 아래 탭 막대 — 현재 탭은 연초록 면 + 초록 글자, 안 읽은 건수 배지(시안 `.m-tabbar`).
// 탭 구성(어떤 탭을 둘지)은 앱이 정한다 — 이 위젯은 그리기만 한다.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:baraeda_ui/widgets/core/pressable.dart';
import 'package:flutter/material.dart';

/// 탭 하나. [badge] 가 0 보다 크면 건수 배지, [dotBadge] 면 점만 보인다.
class BaraedaTabItem {
  const new({
    required this.icon,
    required this.label,
    this.badge = 0,
    this.dotBadge = false,
  });

  /// Lucide 아이콘 이름.
  final String icon;
  final String label;
  final int badge;
  final bool dotBadge;
}

/// 아래 탭 막대. 탭 한 칸의 높이는 56 이상이다.
class BaraedaTabBar extends StatelessWidget {
  const new({
    required this.items,
    required this.currentIndex,
    required this.onChanged,
    super.key,
  });

  final List<BaraedaTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceChrome,
        border: Border(top: BorderSide(color: colors.borderChrome)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          BaraedaSpacing.space2,
          BaraedaSpacing.space2,
          BaraedaSpacing.space2,
          bottom > BaraedaSpacing.space2 ? bottom : BaraedaSpacing.space2,
        ),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: BaraedaSpacing.space1),
              Expanded(
                child: _Tab(
                  item: items[i],
                  selected: i == currentIndex,
                  onTap: () => onChanged(i),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const new({required this.item, required this.selected, required this.onTap});

  final BaraedaTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = selected ? colors.navActiveText : colors.navText;
    final radius = BorderRadius.circular(BaraedaRadius.control);
    final count = item.badge > 99 ? '99+' : '${item.badge}';
    final spoken = item.badge > 0
        ? '${item.label}, 새 알림 ${item.badge}건'
        : item.label;

    return BaraedaPressable(
      onTap: onTap,
      borderRadius: radius,
      selected: selected,
      semanticLabel: spoken,
      child: Stack(
        // 부모(Expanded)가 준 폭을 그대로 써서 현재 탭의 연초록 면이 칸을 가득 채운다.
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? colors.navActiveBg : Colors.transparent,
              borderRadius: radius,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Column(
                // `Scaffold.bottomNavigationBar` 는 세로 제약이 느슨해서
                // 줄이지 않으면 화면 전체를 먹는다.
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  BaraedaIcon(item.icon, size: 24, color: foreground),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BaraedaTypography.micro.copyWith(
                      color: foreground,
                      fontWeight: selected
                          ? BaraedaFontWeight.bold
                          : BaraedaFontWeight.medium,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (item.badge > 0 || item.dotBadge)
            Positioned(
              top: 3,
              left: 0,
              right: 0,
              child: Align(
                // 아이콘 오른쪽 위 — 가운데에서 6px 오른쪽(시안 `left:calc(50% + 6px)`).
                alignment: Alignment.topCenter,
                child: Transform.translate(
                  offset: const Offset(18, 0),
                  child: _Badge(
                    text: item.badge > 0 ? count : null,
                    colors: colors,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const new({required this.text, required this.colors});

  final String? text;
  final BaraedaColors colors;

  @override
  Widget build(BuildContext context) {
    if (text == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: colors.dangerSolid,
          shape: BoxShape.circle,
        ),
        child: const SizedBox(width: 10, height: 10),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.dangerSolid,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Center(
            widthFactor: 1,
            child: Text(
              text!,
              style: BaraedaTypography.micro.copyWith(
                color: colors.onDangerSolid,
                fontWeight: BaraedaFontWeight.bold,
                height: 1.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
