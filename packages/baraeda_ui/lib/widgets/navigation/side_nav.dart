// 관계자 웹 좌측 내비 — 폭 248, 크롬 면(오프화이트 + 우측 선).
// 원본: `frontend/design-system/components/navigation/SideNav.jsx`.
//
// 로고 자리는 나눔명조 워드마크 텍스트로 그린다(이미지·아이콘 로고 금지 — readme.md
// ICONOGRAPHY "wordmark-only logo" 규칙).

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:flutter/material.dart';

/// [SideNav] 한 항목.
@immutable
class SideNavItem {
  const SideNavItem({
    required this.value,
    required this.label,
    required this.icon,
    this.badge,
  });

  final String value;
  final String label;

  /// Lucide 아이콘 이름.
  final String icon;

  /// 지정하면 항목 오른쪽에 배지 숫자를 그린다.
  final int? badge;
}

/// 관계자 웹 좌측 내비. 폭이 고정(248)인 크롬 면 — 모바일 화면에는 두지 않는다.
class SideNav extends StatelessWidget {
  const SideNav({
    required this.items,
    super.key,
    this.value,
    this.onChanged,
    this.academy,
  });

  final List<SideNavItem> items;
  final String? value;
  final ValueChanged<String>? onChanged;

  /// 로고 아래 학원 이름.
  final String? academy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      container: true,
      child: Container(
        width: BaraedaSpacing.sideNavWidth,
        padding: const EdgeInsets.symmetric(
          horizontal: BaraedaSpacing.space3,
          vertical: BaraedaSpacing.space5,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceChrome,
          border: Border(right: BorderSide(color: colors.borderChrome)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                10,
                0,
                10,
                BaraedaSpacing.space5,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '바래다',
                    style: TextStyle(
                      fontFamily: BaraedaFontFamily.serif,
                      fontWeight: BaraedaFontWeight.black,
                      fontSize: 24,
                      height: 1,
                      letterSpacing: -0.72,
                      color: colors.textOnChrome,
                    ),
                  ),
                  if (academy != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        academy!,
                        style: BaraedaTypography.micro.copyWith(
                          color: colors.textOnChromeMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _SideNavButton(
                    item: item,
                    selected: item.value == value,
                    onTap: onChanged == null
                        ? null
                        : () => onChanged!(item.value),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideNavButton extends StatelessWidget {
  const _SideNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final SideNavItem item;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = selected ? colors.navActiveText : colors.navText;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: selected ? colors.navActiveBg : Colors.transparent,
          borderRadius: BorderRadius.circular(BaraedaRadius.sm),
          child: InkWell(
            onTap: onTap,
            focusColor: colors.focusRing.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(BaraedaRadius.sm),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  BaraedaIcon(item.icon, size: 18, color: foreground),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.label,
                      style: BaraedaTypography.bodySm.copyWith(
                        height: 1,
                        fontWeight: selected
                            ? BaraedaFontWeight.medium
                            : BaraedaFontWeight.regular,
                        color: foreground,
                      ),
                    ),
                  ),
                  if (item.badge != null)
                    Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.statusMissed,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${item.badge}',
                        style: BaraedaTypography.labelSm.copyWith(
                          fontSize: 11,
                          height: 20 / 11,
                          color: colors.textInverse,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
