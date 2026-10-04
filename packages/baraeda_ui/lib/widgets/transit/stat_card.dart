// 관계자 웹 대시보드 지표 — 운행 중 노선, 탑승 완료, 미탑승, 미등원.
// 원본: `frontend/design-system/components/transit/StatCard.jsx`.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:flutter/material.dart';

/// 숫자 강조 색. missed 는 화면당 한 번만 쓴다(readme.md 상태 컬러 절제 규칙).
enum StatCardTone { neutral, boarded, moving, missed }

/// 관계자 웹 대시보드 지표 카드.
class StatCard extends StatelessWidget {
  const new({
    super.key,
    this.label,
    this.value,
    this.unit,
    this.tone = StatCardTone.neutral,
    this.icon,
    this.sub,
  });

  final String? label;

  /// 지표 숫자. 문자열로 받아 콤마·단위 표기를 호출자가 정한다.
  final String? value;

  /// '명', '개' 등.
  final String? unit;
  final StatCardTone tone;
  final String? icon;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shadow = Theme.of(context).brightness == Brightness.dark
        ? BaraedaShadows.cardDark
        : BaraedaShadows.cardLight;
    final toneColor = switch (tone) {
      StatCardTone.neutral => colors.textPrimary,
      StatCardTone.boarded => colors.statusBoarded,
      StatCardTone.moving => colors.statusMoving,
      StatCardTone.missed => colors.statusMissed,
    };

    return Semantics(
      container: true,
      label: [label, value, unit, sub].whereType<String>().join(' · '),
      // 합친 라벨이 있으니 자식 Text 는 가린다 — 두 번 읽히지 않게(F07-10).
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(BaraedaSpacing.cardPadding),
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          borderRadius: BorderRadius.circular(BaraedaRadius.card),
          boxShadow: shadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    BaraedaIcon(icon!, size: 14, color: colors.textSecondary),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label!,
                    style: BaraedaTypography.micro.copyWith(
                      height: 1,
                      fontWeight: BaraedaFontWeight.medium,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value ?? '',
                    // 시안 `.m-stat b` — 30px 나눔명조 700 · 숫자 폭 고정.
                    style: BaraedaTypography.h2.copyWith(
                      height: 1.1,
                      color: toneColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (unit != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      unit!,
                      style: BaraedaTypography.caption.copyWith(
                        height: 1,
                        fontWeight: BaraedaFontWeight.medium,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (sub != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  sub!,
                  style: BaraedaTypography.micro.copyWith(
                    height: 1.4,
                    color: colors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
