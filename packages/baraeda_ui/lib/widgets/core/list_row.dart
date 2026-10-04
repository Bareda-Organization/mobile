// 목록 칸 — 높이 56 이상, 앞 칸 · 제목 · 보조 줄 · 뒤 칸(시안 `.m-row`).
// 긴 이름 규칙: 승하차지 · 학원 이름은 제목 두 줄까지 보이고 그 뒤는 `…`,
// **사람 이름은 자르지 않고 줄을 바꾼다**. 보조 줄도 두 줄까지 보인다(C2).

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/motion.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:flutter/material.dart';

/// 목록 칸 한 줄. 여러 줄은 [BaraedaListGroup] 안에 둔다.
class BaraedaListRow extends StatefulWidget {
  const new({
    required this.title,
    super.key,
    this.subtitle,
    this.leadingIcon,
    this.leading,
    this.trailing,
    this.onTap,
    this.done = false,
    this.unread = false,
    this.titleIsPersonName = false,
  });

  final String title;

  /// 보조 줄 — 두 줄까지 보인다(C2).
  final String? subtitle;

  /// 앞 칸 아이콘(Lucide 이름). 36×36 연한 면 안에 그린다. [leading] 이 우선한다.
  final String? leadingIcon;
  final Widget? leading;

  /// 뒤 칸 — 칩 · 시각 · 쉐브론 등.
  final Widget? trailing;

  /// null 이면 눌리지 않는 줄이다(반응 없음).
  final VoidCallback? onTap;

  /// 끝난 줄 — 제목이 보조 글자색이 된다.
  final bool done;

  /// 안 읽은 줄 — 연한 면 + 굵은 제목.
  final bool unread;

  /// 사람 이름이면 자르지 않고 줄을 바꾼다. 아니면 두 줄에서 `…`.
  final bool titleIsPersonName;

  @override
  State<BaraedaListRow> createState() => _BaraedaListRowState();
}

class _BaraedaListRowState extends State<BaraedaListRow> {
  bool _pressed = false;

  void _set(bool v) {
    if (widget.onTap == null || _pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lead =
        widget.leading ??
        (widget.leadingIcon == null
            ? null
            : Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.statusIdleSoft,
                  borderRadius: BorderRadius.circular(BaraedaRadius.sm),
                ),
                child: Center(
                  child: BaraedaIcon(
                    widget.leadingIcon!,
                    color: colors.textPrimary,
                  ),
                ),
              ));

    final background = _pressed
        ? colors.accentPrimarySoft
        : (widget.unread ? colors.accentPrimarySoft : Colors.transparent);

    return Semantics(
      container: true,
      button: widget.onTap != null,
      enabled: widget.onTap != null ? true : null,
      child: AnimatedContainer(
        duration: BaraedaDuration.press,
        color: background,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            onTapDown: widget.onTap == null ? null : (_) => _set(true),
            onTapUp: widget.onTap == null ? null : (_) => _set(false),
            onTapCancel: widget.onTap == null ? null : () => _set(false),
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: colors.focusRing.withValues(alpha: 0.32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: BaraedaSpacing.rowMinHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    if (lead != null) ...[
                      lead,
                      const SizedBox(width: BaraedaSpacing.space3),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            maxLines: widget.titleIsPersonName ? null : 2,
                            overflow: widget.titleIsPersonName
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: BaraedaTypography.body.copyWith(
                              fontWeight: widget.unread
                                  ? BaraedaFontWeight.bold
                                  : BaraedaFontWeight.medium,
                              color: widget.done
                                  ? colors.textSecondary
                                  : colors.textPrimary,
                              height: 1.3,
                            ),
                          ),
                          if (widget.subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Text(
                                widget.subtitle!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: BaraedaTypography.caption.copyWith(
                                  color: colors.textSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (widget.trailing != null) ...[
                      const SizedBox(width: BaraedaSpacing.space2),
                      widget.trailing!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 목록 칸 묶음 — 흰 카드 하나 안에 줄 사이 1px 선(시안 `.m-list`).
class BaraedaListGroup extends StatelessWidget {
  const new({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
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
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, color: colors.borderSubtle),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
