import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/roster/domain/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_interaction.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_widgets.dart';

/// 학생 행 아래의 처리 단추 줄 — 상태별로 탑승 · 미승차 · 하차 · 연락 기록 · 되돌리기를 보인다.
class RosterStudentActions extends StatelessWidget {
  const new({
    required this.runId,
    required this.student,
    required this.direction,
    required this.busy,
    required this.interaction,
    super.key,
  });

  final String runId;
  final RosterStudent student;
  final RunDirection direction;
  final bool busy;
  final RosterInteraction interaction;

  @override
  Widget build(BuildContext context) {
    final riderId = student.riderId;
    // 연결된 보호자가 없으면(명단 번호가 비어 옴) 걸 곳이 없어 단추를 그리지 않는다. 번호 자체는 마스킹돼 있어
    // 누른 순간 서버에서 원번호를 따로 받는다(Ruling 482).
    final call = student.guardianPhone == null
        ? null
        : RosterCallButton(
            onPressed: busy ? null : () => interaction.onCall(runId, riderId),
          );
    final revert = Align(
      alignment: Alignment.centerRight,
      child: BaraedaButton(
        label: '되돌리기',
        size: BaraedaButtonSize.sm,
        variant: BaraedaButtonVariant.ghost,
        onPressed: busy
            ? null
            : () => interaction.onConfirmRevert(runId, student),
      ),
    );
    switch (student.status) {
      case RiderStatus.waiting:
        // [탑승] 은 등원 승하차지의 일이다(C-07 · BRD-01) — 하원은 운행 시작에 전원 자동 승차라 서버가
        // `waiting→boarded` 를 막는다. [미승차] 는 하원에서도 남긴다: 종료 보류 회차의 남은 학생을
        // [되돌리기] → [미승차] 로 정리해 회차를 끝내는 유일한 경로다(BR-031 · C-15).
        final canBoard = direction == RunDirection.toAcademy;
        // 처리 단추가 [미승차] 보다 넓다 — 자주 누르는 쪽이 크다.
        return _ActionRow(
          call: call,
          items: [
            if (canBoard)
              (
                17,
                BaraedaButton(
                  label: '탑승',
                  icon: 'check',
                  block: true,
                  onPressed: busy
                      ? null
                      : () => interaction.onUpdateStatus(
                          runId,
                          riderId,
                          RiderStatus.boarded,
                        ),
                ),
              ),
            (
              10,
              BaraedaButton(
                label: '미승차',
                variant: BaraedaButtonVariant.dangerOutline,
                block: true,
                onPressed: busy
                    ? null
                    : () => interaction.onConfirmNoShow(
                        runId,
                        riderId,
                        student.name,
                      ),
              ),
            ),
          ],
        );
      case RiderStatus.boarded:
        // 하차 처리는 하원 승하차지의 일이다(C-07 · BRD-02) — 등원은 종료 때 전원
        // 자동 하차라 [하차] 가 없다. 잘못 눌린 승차를 바로잡는 [되돌리기] 는
        // 방향과 무관하다.
        final canAlight = direction == RunDirection.fromAcademy;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canAlight || call != null)
              _ActionRow(
                call: call,
                items: [
                  if (canAlight)
                    (
                      1,
                      BaraedaButton(
                        label: '하차',
                        icon: 'check',
                        block: true,
                        onPressed: busy
                            ? null
                            : () => interaction.onUpdateStatus(
                                runId,
                                riderId,
                                RiderStatus.alighted,
                              ),
                      ),
                    ),
                ],
              ),
            revert,
          ],
        );
      case RiderStatus.noShow:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ActionRow(
              call: call,
              items: [
                (
                  1,
                  BaraedaButton(
                    label: '연락 기록',
                    variant: BaraedaButtonVariant.secondary,
                    block: true,
                    onPressed: busy
                        ? null
                        : () => interaction.onOpenNoShow(riderId),
                  ),
                ),
              ],
            ),
            revert,
          ],
        );
      case RiderStatus.alighted:
        return revert;
      case RiderStatus.absent:
        // 학생 행이 배지로 대체해 도달하지 않지만 exhaustiveness 를 위해 채운다.
        return const SizedBox.shrink();
    }
  }
}

/// 전화 단추(있으면) 뒤에 단추들을 flex 비율대로 한 줄에 놓는다.
class _ActionRow extends StatelessWidget {
  const new({required this.call, required this.items});

  final Widget? call;

  /// (flex, 단추) 쌍.
  final List<(int, Widget)> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ?call,
        if (call != null) const SizedBox(width: 8),
        for (final (i, item) in items.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(flex: item.$1, child: item.$2),
        ],
      ],
    );
  }
}
