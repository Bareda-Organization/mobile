import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/runs/presentation/run_display.dart';

/// 회차 라디오 칸 — 운행이 시작됐거나 끝났거나 마감이 지난 회차는 이유와 함께 꺼진다(탑승 취소는 홈에서).
class ChangeRequestRunChoices extends ConsumerWidget {
  const new({
    required this.runs,
    required this.selectedRunId,
    required this.onSelected,
    super.key,
  });

  final List<StudentRun> runs;
  final String? selectedRunId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.read(clockProvider).now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final run in runs) ...[
          if (run != runs.first) const SizedBox(height: BaraedaSpacing.space2),
          BaraedaChoiceTile(
            title: '${run.direction.label} · ${formatClock(run.departTime)} 출발',
            subtitle: '${run.stop.name} · ${run.busNo}',
            selected: run.runId == selectedRunId,
            disabledReason: switch (run.runStatus) {
              RunStatus.moving => '운행이 시작되어 바꿀 수 없어요 · 탑승 취소는 홈에서',
              RunStatus.finished => '운행이 끝났어요',
              // 운행은 시작 전이어도 출발 + 10분이 지나면 서버가 ③ 으로 닫는다(`Ruling 870`).
              RunStatus.idle || RunStatus.confirmed =>
                changeZoneOf(run, now) == ChangeZone.closed
                    ? '변경 신청 마감이 지났어요 · 탑승 취소는 홈에서'
                    : null,
            },
            trailing: _RunChip(run),
            onTap: () => onSelected(run.runId),
          ),
        ],
      ],
    );
  }
}

/// 회차 칸 오른쪽 상태 알약 — 이동 중 · 종료 · 확정 · 확정 전.
class _RunChip extends StatelessWidget {
  const new(this.run);

  final StudentRun run;

  @override
  Widget build(BuildContext context) => switch (run.runStatus) {
    RunStatus.moving => const BaraedaStatusPill(
      status: BaraedaStatus.moving,
      label: '이동 중',
    ),
    RunStatus.finished => const BaraedaStatusPill(
      status: BaraedaStatus.idle,
      label: '종료',
    ),
    RunStatus.confirmed => const BaraedaStatusPill(
      status: BaraedaStatus.boarded,
      label: '확정',
    ),
    RunStatus.idle => BaraedaStatusPill(
      status: run.confirmed ? BaraedaStatus.boarded : BaraedaStatus.waiting,
      label: run.confirmed ? '확정' : '확정 전',
    ),
  };
}
