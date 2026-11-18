import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:baraeda_ui/widgets/core/status_pill.dart';
import 'package:baraeda_ui/widgets/core/word_wrap_text.dart';
import 'package:baraeda_ui/widgets/feedback/notification_tile.dart';
import 'package:flutter/material.dart';

/// 카드형 알림 한 줄(시안) — 안 읽은 행은 연두 면이고, 누를 수 있는 읽은 행은 오른쪽에 쉐브론이 있다.
class NotificationCardRow extends StatelessWidget {
  /// [tile] 의 값으로 카드 안의 행을 그린다.
  const new(this.tile, {super.key});

  final NotificationTile tile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final onTap = tile.onTap;

    return Semantics(
      button: onTap != null,
      onTap: onTap,
      label: [
        if (tile.unread) '안 읽음',
        if (tile.important) '중요',
        tile.kindLabel,
        tile.title,
        tile.body,
        tile.timeSpoken,
        tile.who,
      ].whereType<String>().join(', '),
      excludeSemantics: true,
      child: Material(
        color: tile.unread ? colors.accentPrimarySoft : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          focusColor: colors.focusRing.withValues(alpha: 0.32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.all(BaraedaSpacing.space3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    key: NotificationTile.glyphKey,
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    // 종류 색은 알약이 맡는다 — 아이콘 칸은 종류 · 읽음과 상관없이 옅은 면 + 진한 아이콘(시안).
                    decoration: BoxDecoration(
                      color: colors.statusIdleSoft,
                      borderRadius: BorderRadius.circular(BaraedaRadius.md),
                    ),
                    child: BaraedaIcon(tile.icon, color: colors.textPrimary),
                  ),
                  const SizedBox(width: BaraedaSpacing.space3),
                  Expanded(child: _CardTexts(tile, colors)),
                  const SizedBox(width: BaraedaSpacing.space2),
                  _CardTrailing(tile, colors),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 카드 행의 글 칸 — 제목 · 본문 · `종류 알약 · 시각 · 자녀 이름` 한 줄.
class _CardTexts extends StatelessWidget {
  const new(this.tile, this.colors);

  final NotificationTile tile;
  final BaraedaColors colors;

  @override
  Widget build(BuildContext context) {
    final body = tile.body;
    final name = tile.who;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WordWrapText(
          tile.title,
          style: BaraedaTypography.body.copyWith(
            height: 1.35,
            fontWeight: tile.unread
                ? BaraedaFontWeight.bold
                : BaraedaFontWeight.regular,
          ),
        ),
        if (body != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: WordWrapText(
              body,
              style: BaraedaTypography.bodySm.copyWith(
                height: 1.4,
                color: colors.textSecondary,
              ),
            ),
          ),
        const SizedBox(height: BaraedaSpacing.space2),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: BaraedaSpacing.space2,
          runSpacing: BaraedaSpacing.space1,
          children: [
            BaraedaStatusPill(status: tile.status, label: tile.kindLabel),
            Text(
              tile.time,
              style: BaraedaTypography.caption.copyWith(
                color: colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (name != null)
              Text(
                '· $name',
                style: BaraedaTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 카드 행의 오른쪽 끝 — 안 읽음 점, 아니면 누를 수 있을 때의 쉐브론.
class _CardTrailing extends StatelessWidget {
  const new(this.tile, this.colors);

  final NotificationTile tile;
  final BaraedaColors colors;

  @override
  Widget build(BuildContext context) {
    if (tile.unread) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Container(
          key: NotificationTile.unreadDotKey,
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: colors.accentPrimary,
            shape: BoxShape.circle,
          ),
        ),
      );
    }
    if (tile.onTap != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: BaraedaIcon('chevron-right', color: colors.textTertiary),
      );
    }
    return const SizedBox.shrink();
  }
}
