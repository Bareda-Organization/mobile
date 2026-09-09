// 앱 하단 탭 — 학부모·학생 앱 4탭, 매니저 앱 3탭.
// 원본: `frontend/design-system/components/navigation/TabBar.jsx`.
//
// Flutter `material.TabBar` 와 이름이 겹칠 수 있어 `Baraeda` 접두를 붙인다
// (Dialog·BottomSheet 와 같은 원칙 — 브리프에 명시되진 않았으나 동일 판단으로 확장).

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:flutter/material.dart';

/// [BaraedaTabBar] 한 항목.
@immutable
class BaraedaTabBarItem {
  const BaraedaTabBarItem({
    required this.value,
    required this.label,
    required this.icon,
    this.badge,
  });

  final String value;
  final String label;

  /// Lucide 아이콘 이름.
  final String icon;

  /// 지정하면 아이콘 우상단에 배지 숫자를 그린다.
  final int? badge;
}

/// 앱 하단 탭 바. 항목 수가 고정(3~4개)이라 [Row] 로 구성한다.
class BaraedaTabBar extends StatelessWidget {
  const BaraedaTabBar({
    required this.items,
    super.key,
    this.value,
    this.onChanged,
  });

  final List<BaraedaTabBarItem> items;
  final String? value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: BaraedaSpacing.tabBarHeight,
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: _TabBarButton(
                item: item,
                selected: item.value == value,
                onTap: onChanged == null ? null : () => onChanged!(item.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabBarButton extends StatelessWidget {
  const _TabBarButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final BaraedaTabBarItem item;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = selected ? colors.accentPrimary : colors.textTertiary;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          focusColor: colors.focusRing.withValues(alpha: 0.32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  BaraedaIcon(item.icon, size: 24, color: tint),
                  if (item.badge != null)
                    Positioned(
                      top: -3,
                      right: -8,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 16),
                        height: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.statusMissed,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${item.badge}',
                          style: BaraedaTypography.labelSm.copyWith(
                            fontSize: 10,
                            height: 1.4,
                            color: colors.textInverse,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                style: BaraedaTypography.labelSm.copyWith(
                  fontSize: 11,
                  height: 1,
                  fontWeight: selected
                      ? BaraedaFontWeight.medium
                      : BaraedaFontWeight.regular,
                  color: tint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
