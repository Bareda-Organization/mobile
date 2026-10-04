import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';

/// 홈 맨 위 큰 카드 — 지금 다룰 회차 하나(시안 `home-driver` · `home-escort`).
///
/// 출발 시각(나눔명조 큰 숫자) · 몇 호차 · 방향 · (기사만) 출발지→도착지 · 숫자 3칸. 숫자 줄은 확정 전이라
/// 서버가 세지 않은 회차(`rider_count == null`)면 통째로 숨긴다 — 0 으로 그리면 "탑승자 0명" 으로 읽힌다.
class FocusRunCard extends StatelessWidget {
  const new({
    required this.run,
    required this.now,
    required this.caption,
    required this.forEscort,
    super.key,
    this.footer,
  });

  final ManagerRun run;
  final DateTime now;

  /// 왼쪽 위 작은 글 — `다음 운행` · `지금 명단`.
  final String caption;

  /// 동승자는 출발지·도착지 대신 미등원 수를 보인다.
  final bool forEscort;

  /// 숫자 줄 아래 — 동승자의 `명단 열기` 단추.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (status, statusLabel) = runStatusChip(run);
    final riders = run.riderCount;
    final stops = run.stopCount;
    return BaraedaCard(
      highlight: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  caption,
                  style: BaraedaTypography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              BaraedaStatusPill(
                status: status,
                label: statusLabel,
                size: BaraedaStatusPillSize.lg,
              ),
            ],
          ),
          const SizedBox(height: BaraedaSpacing.space2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                hhmm(run.departTime),
                style: BaraedaTypography.display.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: BaraedaSpacing.space2),
              Flexible(
                child: Text(
                  departsInLabel(run.departTime, now),
                  style: BaraedaTypography.body.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: BaraedaSpacing.space1),
          Text(
            '${run.busNo} · ${directionLabel(run.direction)}',
            style: BaraedaTypography.title.copyWith(color: colors.textPrimary),
          ),
          if (!forEscort) ...[
            const SizedBox(height: BaraedaSpacing.space3),
            _RouteEnds(
              origin: run.origin,
              destination: run.destination,
              between: stops == null || stops < 2 ? null : stops - 1,
            ),
          ],
          if (riders != null || stops != null) ...[
            const SizedBox(height: BaraedaSpacing.space3),
            Divider(height: 1, color: colors.borderSubtle),
            const SizedBox(height: BaraedaSpacing.space3),
            _StatsRow(
              stats: [
                if (riders != null) _Stat('$riders명', '탑승 예정'),
                if (stops != null) _Stat('$stops곳', '승하차지'),
                if (forEscort && run.absentCount != null)
                  _Stat('${run.absentCount}명', '미등원'),
                if (!forEscort)
                  _Stat(
                    '${hhmm(run.startWindowFrom)}~${hhmm(run.startWindowTo)}',
                    '시작 가능',
                  ),
              ],
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: BaraedaSpacing.space4),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// 회차 상태 → 칩 모양 · 문구. 홈 큰 카드와 "다른 회차" 목록이 같이 쓴다.
(BaraedaStatus, String) runStatusChip(ManagerRun run) {
  if (!run.confirmed && run.runStatus != RunStatus.moving) {
    return (BaraedaStatus.waiting, '확정 전');
  }
  return switch (run.runStatus) {
    RunStatus.moving => (BaraedaStatus.moving, '운행 중'),
    RunStatus.finished => (BaraedaStatus.idle, '종료'),
    RunStatus.idle => (BaraedaStatus.waiting, '확정 전'),
    RunStatus.confirmed => (BaraedaStatus.boarded, '확정'),
  };
}

class _Stat {
  const new(this.value, this.label);

  final String value;
  final String label;
}

class _StatsRow extends StatelessWidget {
  const new({required this.stats});

  final List<_Stat> stats;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) VerticalDivider(width: 1, color: colors.borderSubtle),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 시작 가능 시간대처럼 긴 값은 줄이지 말고 글자를 줄여 한 줄에 담는다.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        stats[i].value,
                        maxLines: 1,
                        style: BaraedaTypography.body.copyWith(
                          fontWeight: BaraedaFontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      stats[i].label,
                      style: BaraedaTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 출발지 ○ ┄ 도착지 ● — 가운데 점선에 거쳐 가는 승하차지 수를 적는다.
class _RouteEnds extends StatelessWidget {
  const new({
    required this.origin,
    required this.destination,
    required this.between,
  });

  final String origin;
  final String destination;
  final int? between;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget dot({required bool filled}) => Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? colors.accentPrimary : colors.surfaceCard,
        border: Border.all(
          color: filled ? colors.accentPrimary : colors.textPrimary,
          width: 2,
        ),
      ),
    );
    final nameStyle = BaraedaTypography.body.copyWith(
      fontWeight: BaraedaFontWeight.bold,
      color: colors.textPrimary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            dot(filled: false),
            const SizedBox(width: BaraedaSpacing.space3),
            Expanded(
              child: Text(
                origin,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: nameStyle,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 7),
          child: Row(
            children: [
              SizedBox(
                width: 2,
                height: 22,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: colors.borderControl, width: 2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 19),
              if (between != null)
                Text(
                  '승하차지 $between곳 거쳐',
                  style: BaraedaTypography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        Row(
          children: [
            dot(filled: true),
            const SizedBox(width: BaraedaSpacing.space3),
            Expanded(
              child: Text(
                destination,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: nameStyle,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
