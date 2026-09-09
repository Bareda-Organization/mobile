// 알림 타임라인의 기본 항목 — 누가 → 무엇을 → 언제 → 어디서 순서로 채운다.
// 원본: `frontend/design-system/components/feedback/NotificationCard.jsx`.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/baraeda_status.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:baraeda_ui/widgets/core/status_pill.dart';
import 'package:flutter/material.dart';

/// 학부모·학생 앱 알림 카드. 제목은 세리프, 시각·정류장은 산세리프.
///
/// [status]는 [BaraedaStatus] 4종 중 하나이며 [BaraedaStatusPill] 에
/// 그대로 전달된다 — 값 집합은 core 쪽과 1:1 로 맞춰야 한다.
class NotificationCard extends StatelessWidget {
  const NotificationCard({
    super.key,
    this.status = BaraedaStatus.boarded,
    this.statusLabel,
    this.title,
    this.meta,
    this.sub,
    this.time,
    this.unread = false,
    this.onTap,
  });

  final BaraedaStatus status;

  /// pill 안 문구. 비우면 [BaraedaStatusPill] 이 상태 기본 라벨을 쓴다.
  final String? statusLabel;

  /// 결론 한 줄. 예: '하준이가 승차했어요'.
  final String? title;

  /// 시각 · 정류장. 예: '8:37 · 한화아파트 정류장'.
  final String? meta;

  /// 보조 한 줄. 예: '도착 예정 8:58'.
  final String? sub;

  /// 오른쪽 위 상대 시각.
  final String? time;

  final bool unread;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shadow = Theme.of(context).brightness == Brightness.dark
        ? BaraedaShadows.cardDark
        : BaraedaShadows.cardLight;

    return Semantics(
      button: onTap != null,
      label: [title, meta].whereType<String>().join(' · '),
      child: Material(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(BaraedaRadius.card),
        child: InkWell(
          onTap: onTap,
          focusColor: colors.focusRing.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(BaraedaRadius.card),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: BaraedaSpacing.space4,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BaraedaRadius.card),
              boxShadow: shadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _NotificationBody(this)),
                if (onTap != null)
                  Padding(
                    padding: const EdgeInsets.only(left: BaraedaSpacing.space2),
                    // size 는 BaraedaIcon 기본값 20 과 같아 생략한다.
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
    );
  }
}

class _NotificationBody extends StatelessWidget {
  const _NotificationBody(this.card);

  final NotificationCard card;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            BaraedaStatusPill(status: card.status, label: card.statusLabel),
            if (card.unread)
              Padding(
                padding: const EdgeInsets.only(left: BaraedaSpacing.space2),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: colors.accentSecondary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            if (card.time != null) ...[
              const Spacer(),
              Text(
                card.time!,
                style: BaraedaTypography.micro.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ],
        ),
        if (card.title != null)
          Padding(
            padding: const EdgeInsets.only(top: BaraedaSpacing.space3),
            child: Text(
              card.title!,
              style: BaraedaTypography.h3.copyWith(fontSize: 20, height: 1.35),
            ),
          ),
        if (card.meta != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(card.meta!, style: BaraedaTypography.bodySm),
          ),
        if (card.sub != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              card.sub!,
              style: BaraedaTypography.micro.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}
