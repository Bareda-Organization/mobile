import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/features/roster/domain/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_interaction.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_student_actions.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_widgets.dart';

/// 명단의 학생 한 명 — 상태 칩 · 배지(금일 삭제 · 전송 대기) · 미승차 만료 안내와 처리 단추를 정한다.
class RosterStudentRow extends StatelessWidget {
  const new({
    required this.runId,
    required this.student,
    required this.direction,
    required this.canDecide,
    required this.photoHeaders,
    required this.queued,
    required this.interaction,
    super.key,
  });

  final String runId;
  final RosterStudent student;
  final RunDirection direction;
  final bool canDecide;
  final Map<String, String>? photoHeaders;

  /// 이 학생의 처리가 통신 두절로 대기열에 쌓여 있는가.
  final bool queued;
  final RosterInteraction interaction;

  @override
  Widget build(BuildContext context) {
    final busy = interaction.pendingRiderIds.contains(student.riderId);
    // Ruling 341, BR-016 — `absent`(`change=removed`) 행은 버스 간 이동으로 빠진
    // 학생이라 조작 대상이
    // 아니다. 배지만 보여주고 [탑승]·[미승차] 등은 아예 그리지 않는다(canDecide 여부와 무관).
    final badge = student.status == RiderStatus.absent
        ? const BaraedaBadge(label: '금일 삭제', tone: BaraedaBadgeTone.removed)
        : queued
        ? const BaraedaBadge(label: '전송 대기', tone: BaraedaBadgeTone.amber)
        : null;
    final noShowCase = student.noShowCase;
    final expiry = student.status == RiderStatus.noShow && noShowCase != null
        ? '${hhmm(noShowCase.expiresAt)} 까지 연락 대기'
        : null;
    return RosterStudentTile(
      student: student,
      ride: _rideStatusOf(student.status),
      photoHeaders: photoHeaders,
      metaExtra: expiry,
      badge: badge,
      busy: busy,
      // 혼자 귀가 여부는 하원에서만 뜻이 있다(C-07) — 등원 회차에는 경고를 내지 않는다.
      warnCannotGoAlone: direction == RunDirection.fromAcademy,
      actions: badge != null || !canDecide
          ? null
          : RosterStudentActions(
              runId: runId,
              student: student,
              direction: direction,
              busy: busy,
              interaction: interaction,
            ),
    );
  }
}

RideStatus _rideStatusOf(RiderStatus status) => switch (status) {
  RiderStatus.waiting => RideStatus.waiting,
  RiderStatus.boarded => RideStatus.boarded,
  RiderStatus.alighted => RideStatus.alighted,
  RiderStatus.noShow => RideStatus.missed,
  RiderStatus.absent => RideStatus.absent,
};
