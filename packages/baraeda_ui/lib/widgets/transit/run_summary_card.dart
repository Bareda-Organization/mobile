// 오늘 운행 요약 — 학부모 앱 홈, 매니저 앱 운행모드 상단.
// 원본: `frontend/design-system/components/transit/RunSummaryCard.jsx`.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/baraeda_status.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:baraeda_ui/widgets/core/status_pill.dart';
import 'package:flutter/material.dart';

/// 오늘 운행 한 장 요약 카드 — 출발지와 도착지를 나란히 둔다.
class RunSummaryCard extends StatelessWidget {
  const RunSummaryCard({
    super.key,
    this.bus,
    this.leg,
    this.status = BaraedaStatus.moving,
    this.statusLabel,
    this.eta,
    this.origin,
    this.destination,
    this.manager,
    this.driver,
    this.onTap,
  });

  /// 예: '3-2호차'.
  final String? bus;

  /// 예: '등원' / '하원'.
  final String? leg;

  final BaraedaStatus status;
  final String? statusLabel;

  /// 결론 한 줄. 예: '약 5분 후 도착합니다'.
  final String? eta;

  /// 출발지(`API_SPEC §4.1` `origin`).
  final String? origin;

  /// 도착지(`API_SPEC §4.1` `destination`).
  final String? destination;

  final String? manager;
  final String? driver;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shadow = Theme.of(context).brightness == Brightness.dark
        ? BaraedaShadows.cardDark
        : BaraedaShadows.cardLight;
    final crew = [
      if (driver != null) '기사 $driver',
      if (manager != null) '동승 매니저 $manager',
    ].join(' · ');

    return Semantics(
      button: onTap != null,
      label: [bus, leg, statusLabel, eta].whereType<String>().join(' · '),
      child: Material(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(BaraedaRadius.card),
        child: InkWell(
          onTap: onTap,
          focusColor: colors.focusRing.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(BaraedaRadius.card),
          child: Container(
            padding: const EdgeInsets.all(BaraedaSpacing.space5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BaraedaRadius.card),
              boxShadow: shadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    BaraedaStatusPill(status: status, label: statusLabel),
                    const Spacer(),
                    if (bus != null)
                      Text(
                        leg != null ? '$bus · $leg' : bus!,
                        style: BaraedaTypography.labelSm.copyWith(
                          height: 1,
                          fontWeight: BaraedaFontWeight.bold,
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
                if (eta != null)
                  Padding(
                    padding: const EdgeInsets.only(top: BaraedaSpacing.space3),
                    child: Text(
                      eta!,
                      style: BaraedaTypography.h3.copyWith(
                        fontSize: 26,
                        height: 1.3,
                        letterSpacing: -0.39,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: _RunStopTile(
                          icon: 'navigation',
                          // [origin] — **출발지**다(`API_SPEC §4.1`). "현재 이동 중" 으로
                          // 적으면 출발 전 회차에도 버스가 움직이는 것처럼 보인다.
                          label: '출발',
                          value: origin,
                        ),
                      ),
                      const SizedBox(width: BaraedaSpacing.space3),
                      Expanded(
                        child: _RunStopTile(
                          icon: 'map-pin',
                          // [destination] — **도착지**. 그리고 이 서비스에는 공용 정류장
                          // 개념이 부재하고 단위는 승하차지다(`FEATURE_SPEC C-12`).
                          label: '도착',
                          value: destination,
                        ),
                      ),
                    ],
                  ),
                ),
                if (crew.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      crew,
                      style: BaraedaTypography.micro.copyWith(
                        color: colors.textSecondary,
                      ),
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

class _RunStopTile extends StatelessWidget {
  const _RunStopTile({required this.icon, required this.label, this.value});

  final String icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: BaraedaSpacing.space3,
      ),
      decoration: BoxDecoration(
        color: colors.bgSubtle,
        borderRadius: BorderRadius.circular(BaraedaRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BaraedaIcon(icon, size: 13, color: colors.textSecondary),
              const SizedBox(width: 5),
              Text(
                label,
                style: BaraedaTypography.micro.copyWith(
                  height: 1,
                  fontWeight: BaraedaFontWeight.medium,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              value ?? '',
              style: BaraedaTypography.bodySm.copyWith(
                height: 1.3,
                fontWeight: BaraedaFontWeight.medium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
