import 'package:flutter/material.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/roster/domain/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_interaction.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_student_row.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_widgets.dart';

/// 승하차지 한 곳의 카드와 그 안의 학생 행들 — 처리할 학생을 위로 올려 그린다.
class RosterStopSection extends StatelessWidget {
  const new({
    required this.runId,
    required this.stop,
    required this.order,
    required this.isCurrent,
    required this.direction,
    required this.canDecide,
    required this.photoHeaders,
    required this.queuedRiderIds,
    required this.interaction,
    super.key,
  });

  final String runId;
  final RosterStop stop;

  /// 이 목록에서의 번호(1부터) — 서버 `seq` 가 아니다(`Ruling 400`).
  final int order;

  /// 다음에 도착할 곳인가.
  final bool isCurrent;
  final RunDirection direction;
  final bool canDecide;
  final Map<String, String>? photoHeaders;
  final Set<String> queuedRiderIds;
  final RosterInteraction interaction;

  @override
  Widget build(BuildContext context) {
    final phase = stop.arrivedAt != null
        ? RosterStopPhase.arrived
        : isCurrent
        ? RosterStopPhase.current
        : RosterStopPhase.upcoming;
    final students = [...stop.students]
      ..sort(
        (a, b) =>
            (_needsAction(a, direction) ? 0 : 1) -
            (_needsAction(b, direction) ? 0 : 1),
      );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RosterStopCard(
        stop: stop,
        order: order,
        phase: phase,
        expanded:
            phase == RosterStopPhase.current ||
            interaction.expandedStopIds.contains(stop.stopId),
        onToggle: () => interaction.onToggleStop(stop.stopId),
        waitingCount: stop.students
            .where((s) => _needsAction(s, direction))
            .length,
        noShowCount: stop.students
            .where((s) => s.status == RiderStatus.noShow)
            .length,
        children: [
          for (final student in students)
            RosterStudentRow(
              runId: runId,
              student: student,
              direction: direction,
              canDecide: canDecide,
              photoHeaders: photoHeaders,
              queued: queuedRiderIds.contains(student.riderId),
              interaction: interaction,
            ),
        ],
      ),
    );
  }
}

/// 이 학생에게 지금 처리할 일이 있는가 — 등원은 아직 안 탄 학생, 하원은 아직 안 내린 학생. 위로 올린다.
bool _needsAction(RosterStudent s, RunDirection direction) =>
    direction == RunDirection.toAcademy
    ? s.status == RiderStatus.waiting || s.status == RiderStatus.noShow
    : s.status == RiderStatus.boarded || s.status == RiderStatus.waiting;
