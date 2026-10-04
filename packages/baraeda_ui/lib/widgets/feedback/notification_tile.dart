// 알림 목록의 한 줄 — 종류 아이콘 · 제목 · 본문 · 시각. 카드가 아니라 목록 행이다(R44).
// 킷의 `NotificationCard.jsx` 는 알림을 큰 카드로 쌓는다.
// 사용자 지시로 행으로 바꿨다(IMPLEMENTATION_PLAN §4).

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/baraeda_status.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:baraeda_ui/widgets/core/status_pill.dart';
import 'package:baraeda_ui/widgets/core/word_wrap_text.dart';
import 'package:flutter/material.dart';

/// 학부모·학생 앱 알림 목록 행.
///
/// 안 읽음은 **바탕 · 굵은 제목 · 꽉 찬 색 아이콘 원 · 점** 네 겹으로 읽음과 갈린다. 중요 통지는
/// 왼쪽 막대와 `중요` 글자를 함께 쓴다(색만으로 구분하지 않는다). 행 전체가 낭독기에 한 문장으로
/// 읽히고 자식 글자는 가려 같은 말을 두 번 읽지 않는다(F07-10).
/// 알림 한 줄의 모양.
enum NotificationTileStyle {
  /// 전체 폭 행 + 아래 가는 선 + 오른쪽 위 시각(기본 — 매니저 앱).
  row,

  /// 카드 안의 행(시안 학부모·학생 `notifications*`) — 모서리가 둥근 아이콘 · 제목 · 본문 ·
  /// `종류 알약 · 시각 · 자녀 이름` 한 줄 · 안 읽음 점. 한 날의 행들은 목록이 한 카드로 묶는다.
  card,
}

class NotificationTile extends StatelessWidget {
  const new({
    required this.icon,
    required this.status,
    required this.kindLabel,
    required this.title,
    required this.time,
    required this.timeSpoken,
    super.key,
    this.body,
    this.unread = false,
    this.important = false,
    this.onTap,
    this.style = NotificationTileStyle.row,
    this.who,
  });

  /// 시험이 각 부품을 집는 열쇠.
  static const unreadDotKey = ValueKey<String>('notification-unread-dot');
  static const glyphKey = ValueKey<String>('notification-glyph');
  static const importantBarKey = ValueKey<String>('notification-important-bar');

  /// [BaraedaIcon] 이름 — 종류마다 달라야 한다(색만으로 구분하지 않는다).
  final String icon;

  /// 아이콘 원의 색 계열. 미승차·비상은 [BaraedaStatus.missed].
  final BaraedaStatus status;

  /// 낭독 전용 종류 이름 — 화면에는 나오지 않는다(아이콘이 대신 말한다).
  final String kindLabel;

  final String title;
  final String? body;

  /// 오른쪽 시각 표기. 예: `8:37`.
  final String time;

  /// 낭독용 시각. 예: `오전 8시 37분`.
  final String timeSpoken;

  final bool unread;

  /// 중요 통지(NTF-10: 지연 · 미승차 · 노선 변경).
  final bool important;

  /// 모양. 기본은 [NotificationTileStyle.row].
  final NotificationTileStyle style;

  /// 누구 알림인지(자녀 이름) — [NotificationTileStyle.card] 의 메타 줄 끝에
  /// `· 이하준` 으로 붙는다. 낭독에도 읽힌다.
  final String? who;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (solid, soft) = _tone(colors, status);
    if (style == NotificationTileStyle.card) return _buildCard(colors);

    return Semantics(
      button: onTap != null,
      onTap: onTap,
      label: [
        if (unread) '안 읽음',
        if (important) '중요',
        kindLabel,
        title,
        body,
        timeSpoken,
        who,
      ].whereType<String>().join(', '),
      excludeSemantics: true,
      child: Material(
        color: unread ? colors.accentPrimarySoft : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          focusColor: colors.focusRing.withValues(alpha: 0.32),
          child: Stack(
            children: [
              Container(
                constraints: const BoxConstraints(
                  minHeight: BaraedaSpacing.tapMin,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: BaraedaSpacing.gutterMobile,
                  vertical: BaraedaSpacing.space3,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: colors.borderSubtle),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Glyph(
                      icon: icon,
                      solid: solid,
                      soft: soft,
                      filled: unread,
                      colors: colors,
                    ),
                    const SizedBox(width: BaraedaSpacing.space3),
                    Expanded(child: _Texts(this, colors)),
                    const SizedBox(width: BaraedaSpacing.space3),
                    _Meta(this, colors, solid),
                  ],
                ),
              ),
              if (important)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 4,
                  child: ColoredBox(key: importantBarKey, color: solid),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 카드형 한 줄(시안) — 안 읽은 행은 연두 면이고, 누를 수 있는 읽은 행은 오른쪽에 쉐브론이 있다.
  Widget _buildCard(BaraedaColors colors) {
    final (solid, soft) = _tone(colors, status);
    final name = who;

    return Semantics(
      button: onTap != null,
      onTap: onTap,
      label: [
        if (unread) '안 읽음',
        if (important) '중요',
        kindLabel,
        title,
        body,
        timeSpoken,
        name,
      ].whereType<String>().join(', '),
      excludeSemantics: true,
      child: Material(
        color: unread ? colors.accentPrimarySoft : Colors.transparent,
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
                    decoration: BoxDecoration(
                      color: unread ? solid : soft,
                      borderRadius: BorderRadius.circular(BaraedaRadius.md),
                    ),
                    child: BaraedaIcon(
                      icon,
                      color: unread ? colors.textInverse : solid,
                    ),
                  ),
                  const SizedBox(width: BaraedaSpacing.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        WordWrapText(
                          title,
                          style: BaraedaTypography.body.copyWith(
                            height: 1.35,
                            fontWeight: unread
                                ? BaraedaFontWeight.bold
                                : BaraedaFontWeight.regular,
                          ),
                        ),
                        if (body != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: WordWrapText(
                              body!,
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
                            BaraedaStatusPill(status: status, label: kindLabel),
                            Text(
                              time,
                              style: BaraedaTypography.caption.copyWith(
                                color: colors.textSecondary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
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
                    ),
                  ),
                  const SizedBox(width: BaraedaSpacing.space2),
                  if (unread)
                    Padding(
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
                    )
                  else if (onTap != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: BaraedaIcon(
                        'chevron-right',
                        color: colors.textTertiary,
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

/// 상태 → (꽉 찬 색, 옅은 색). 매핑은 `theme/baraeda_colors.dart` 의 상태 색 한 곳에서만 정한다.
(Color, Color) _tone(BaraedaColors c, BaraedaStatus status) => switch (status) {
  BaraedaStatus.boarded => (c.statusBoarded, c.statusBoardedSoft),
  BaraedaStatus.moving => (c.statusMoving, c.statusMovingSoft),
  BaraedaStatus.missed => (c.statusMissed, c.statusMissedSoft),
  BaraedaStatus.idle => (c.statusIdle, c.statusIdleSoft),
  BaraedaStatus.waiting => (c.statusWait, c.statusWaitSoft),
};

/// 종류 아이콘 원 — 안 읽음이면 꽉 찬 색에 반전 글리프, 읽음이면 옅은 색에 상태 색 글리프.
class _Glyph extends StatelessWidget {
  const new({
    required this.icon,
    required this.solid,
    required this.soft,
    required this.filled,
    required this.colors,
  });

  final String icon;
  final Color solid;
  final Color soft;
  final bool filled;
  final BaraedaColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: NotificationTile.glyphKey,
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? solid : soft,
        shape: BoxShape.circle,
      ),
      child: BaraedaIcon(icon, color: filled ? colors.textInverse : solid),
    );
  }
}

class _Texts extends StatelessWidget {
  const new(this.tile, this.colors);

  final NotificationTile tile;
  final BaraedaColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tile.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: BaraedaTypography.bodySm.copyWith(
            height: 1.35,
            color: colors.textPrimary,
            fontWeight: tile.unread
                ? BaraedaFontWeight.bold
                : BaraedaFontWeight.regular,
          ),
        ),
        if (tile.body != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: WordWrapText(
              tile.body!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: BaraedaTypography.micro.copyWith(
                height: 1.4,
                fontWeight: BaraedaFontWeight.regular,
                color: colors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

/// 오른쪽 열 — 시각 · (중요 글자) · (안 읽음 점).
class _Meta extends StatelessWidget {
  const new(this.tile, this.colors, this.solid);

  final NotificationTile tile;
  final BaraedaColors colors;
  final Color solid;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tile.time,
          style: BaraedaTypography.micro.copyWith(
            height: 1.35,
            fontWeight: BaraedaFontWeight.regular,
            color: colors.textSecondary,
          ),
        ),
        if (tile.important || tile.unread)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tile.important)
                  Text(
                    '중요',
                    style: BaraedaTypography.labelSm.copyWith(
                      height: 1.2,
                      fontWeight: BaraedaFontWeight.bold,
                      color: solid,
                    ),
                  ),
                if (tile.important && tile.unread) const SizedBox(width: 6),
                if (tile.unread)
                  Container(
                    key: NotificationTile.unreadDotKey,
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors.accentPrimary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
