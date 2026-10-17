import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';

// 명단 화면(`roster_screen.dart`)에서 떼어 낸 조각 — 연락 대기 띠 · 지난 승하차지 접힘 · 로딩 자리.

/// 미승차 연락 대기 띠 — `오시우 미승차 · 연락 대기 1:12` + `연락`. 1초마다 남은 시간을 다시 그린다.
class NoShowWaitBanner extends ConsumerStatefulWidget {
  const new({required this.student, required this.onContact, super.key});

  final RosterStudent student;
  final VoidCallback onContact;

  @override
  ConsumerState<NoShowWaitBanner> createState() => _NoShowWaitBannerState();
}

class _NoShowWaitBannerState extends ConsumerState<NoShowWaitBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final case_ = widget.student.noShowCase!;
    final left = case_.expiresAt.difference(ref.watch(clockProvider).now());
    final remaining = left.isNegative ? Duration.zero : left;
    final text = remaining == Duration.zero
        ? '${widget.student.name} 미승차 · 연락 대기가 끝났어요'
        : '${widget.student.name} 미승차 · 연락 대기 '
              '${remaining.inMinutes}:'
              '${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';
    return AlertBanner(
      tone: AlertTone.moving,
      icon: 'clock',
      title: text,
      inlineAction: true,
      action: BaraedaButton(
        label: '연락',
        size: BaraedaButtonSize.sm,
        variant: BaraedaButtonVariant.secondary,
        onPressed: widget.onContact,
      ),
    );
  }
}

/// `지난 승하차지 2곳 / 푸른아파트 앞 · 중앙공원 앞 [미승차 1] ›` — 지나온 곳을 한 줄로 접어 둔다.
class PastStopsCard extends StatelessWidget {
  const new({
    required this.stops,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final List<RosterStop> stops;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final noShow = stops
        .expand((s) => s.students)
        .where((s) => s.status == RiderStatus.noShow)
        .length;
    return BaraedaCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(BaraedaRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accentPrimary,
                ),
                child: BaraedaIcon(
                  'check',
                  size: 18,
                  color: colors.textInverse,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '지난 승하차지 ${stops.length}곳',
                      style: BaraedaTypography.body.copyWith(
                        fontWeight: BaraedaFontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      stops.map((s) => s.name).join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: BaraedaTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (noShow > 0) ...[
                const SizedBox(width: 8),
                BaraedaStatusPill(
                  status: BaraedaStatus.missed,
                  label: '미승차 $noShow',
                ),
              ],
              const SizedBox(width: 4),
              BaraedaIcon(
                expanded ? 'chevron-down' : 'chevron-right',
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RosterSkeleton extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.all(16),
    children: const [
      BaraedaSkeleton(height: 72, radius: 16),
      SizedBox(height: 12),
      BaraedaSkeletonList(count: 4),
    ],
  );
}
