import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';

/// 다음 승하차지 큰 카드 — `다음 승하차지 · 3번` + 이름(나눔명조 큰 글자) + 부제 + `명단 ›`(조회 전용 명단).
class NextStopCard extends StatelessWidget {
  const new({
    required this.stop,
    required this.order,
    required this.direction,
    required this.isLast,
    required this.onRoster,
    super.key,
  });

  final RosterStop stop;
  final int order;
  final RunDirection direction;
  final bool isLast;
  final VoidCallback onRoster;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final subtitle = isLast
        ? _lastStopNote(direction)
        : [
            if (stop.change == StopChange.added) '신규',
            '${expectedRidersLabel(direction)} ${stop.students.length}명',
          ].join(' · ');
    return BaraedaCard(
      accent: BaraedaStatus.moving,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${isLast ? '마지막' : '다음'} 승하차지 · $order번',
                  style: BaraedaTypography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  stop.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BaraedaTypography.h2.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: BaraedaTypography.body.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          BaraedaButton(
            label: '명단',
            iconEnd: 'chevron-right',
            size: BaraedaButtonSize.sm,
            variant: BaraedaButtonVariant.ghost,
            onPressed: onRoster,
          ),
        ],
      ),
    );
  }
}

/// `남은 승하차지 3곳 · 미경유 1곳은 건너뛰어요` + 번호 타임라인 — 조회 전용(승하차 처리는 동승자만, M-12).
class RemainingStops extends StatelessWidget {
  const new({
    required this.roster,
    required this.colors,
    required this.queuedStopIds,
    super.key,
  });

  final RosterResponse roster;
  final BaraedaColors colors;

  /// 도착 처리를 기기에 저장해 둔 곳 — 이미 처리한 곳으로 보고 남은 목록에서 뺀다(859).
  final Set<String> queuedStopIds;

  @override
  Widget build(BuildContext context) {
    final remaining = [
      for (final stop in roster.stops)
        if (stop.arrivedAt == null && !queuedStopIds.contains(stop.stopId))
          stop,
    ];
    if (remaining.isEmpty) return const SizedBox.shrink();
    final skipped = remaining
        .where((stop) => stop.change == StopChange.skipped)
        .length;
    final active = remaining.length - skipped;
    final firstActive = remaining.indexWhere(
      (stop) => stop.change != StopChange.skipped,
    );
    return Column(
      key: const Key('remaining-stops'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '남은 승하차지 $active곳',
                style: BaraedaTypography.title.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (skipped > 0)
              Text(
                '미경유 $skipped곳은 건너뛰어요',
                style: BaraedaTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        BaraedaCard(
          child: StopTimeline(
            stops: [
              for (var i = 0; i < remaining.length; i++)
                switch (remaining[i].change) {
                  StopChange.skipped => Stop(
                    name: remaining[i].name,
                    address: '정차 안 함',
                    time: '미경유',
                    state: StopState.skipped,
                  ),
                  _ => Stop(
                    name: remaining[i].name,
                    address: i == remaining.length - 1
                        ? _lastStopNote(roster.direction)
                        : '학생 ${remaining[i].students.length}명'
                              '${_addedSuffix(remaining[i])}',
                    time: remaining[i].change == StopChange.added ? '추가' : null,
                    state: i == firstActive
                        ? StopState.current
                        : StopState.upcoming,
                  ),
                },
            ],
          ),
        ),
      ],
    );
  }
}

/// 마지막 승하차지에 도착하면 일어나는 일 — 등원은 곧 운행 종료, 하원은 탑승 중 학생이 남아 있으면 종료가
/// 보류된다(C-15). 도착 확인 창의 안내와 같은 약속이다.
String _lastStopNote(RunDirection direction) =>
    direction == RunDirection.toAcademy
    ? '도착하면 운행이 끝나요'
    : '학생이 남아 있으면 종료가 보류돼요';

/// 신규로 추가된 승하차지의 부제 꼬리.
String _addedSuffix(RosterStop stop) =>
    stop.change == StopChange.added ? ' · 신규' : '';
