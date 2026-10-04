import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:parent_app/core/runs/presentation/run_display.dart';

/// 진행 막대 한 칸의 상태.
enum ApprovalStepState {
  /// 끝났다 — 체크.
  done,

  /// 지금 여기다 — 번호 + 진한 테두리.
  current,

  /// 아직이다 — 번호 + 옅은 테두리.
  upcoming,

  /// 거절로 끝났다 — ✕.
  rejected,
}

/// 진행 막대 한 칸 — 이름 + 상태 + 아래 작은 글자.
class ApprovalStep {
  const new({required this.label, required this.state, this.caption});

  final String label;
  final ApprovalStepState state;

  /// 칸 아래 작은 글자 — 신청 접수 칸은 신청 시각, 지금 칸은 `진행 중`.
  final String? caption;
}

/// 가입 상태를 단계 셋으로 바꾼다 — `신청 접수 → 학원 확인 → 사용 시작`(거절이면 마지막이 `거절`).
///
/// **학원이 확인한 시각은 어느 칸에도 달지 않는다** — 응답에 그 시각이 없고(`REPORT-MP §1.3`), `status` ·
/// `requested_at` 으로 계산할 수 없는 값을 지어내지 않는다. 시각을 다는 칸은 신청 접수(`requested_at`) 하나다.
List<ApprovalStep> approvalSteps(AccountStatus status, DateTime requestedAt) {
  final received = ApprovalStep(
    label: '신청 접수',
    state: ApprovalStepState.done,
    caption: formatClock(requestedAt),
  );
  return switch (status) {
    AccountStatus.pending => [
      received,
      const ApprovalStep(
        label: '학원 확인',
        state: ApprovalStepState.current,
        caption: '진행 중',
      ),
      const ApprovalStep(label: '사용 시작', state: ApprovalStepState.upcoming),
    ],
    AccountStatus.rejected => [
      received,
      const ApprovalStep(label: '학원 확인', state: ApprovalStepState.done),
      const ApprovalStep(label: '거절', state: ApprovalStepState.rejected),
    ],
    AccountStatus.active => [
      received,
      const ApprovalStep(label: '학원 확인', state: ApprovalStepState.done),
      const ApprovalStep(label: '사용 시작', state: ApprovalStepState.done),
    ],
  };
}

/// 3단계 진행 막대(시안 `pending*`) — 둥근 표시 셋을 선으로 잇고 아래에 이름과 작은 글자를 둔다.
///
/// 상태를 색만으로 알리지 않는다 — 끝남은 체크, 지금은 번호 + 굵은 테두리, 아직은 번호 + 옅은 테두리, 거절은 ✕ 다.
class ApprovalProgress extends StatelessWidget {
  const new({required this.steps, super.key});

  final List<ApprovalStep> steps;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Expanded(
            child: _StepColumn(
              step: steps[i],
              number: i + 1,
              leftLine: i == 0 ? null : _lineDone(steps[i - 1], steps[i]),
              rightLine: i == steps.length - 1
                  ? null
                  : _lineDone(steps[i], steps[i + 1]),
            ),
          ),
      ],
    );
  }

  /// 두 칸 사이 선이 진한가 — 앞 칸이 끝났고 뒷 칸이 아직이 아닐 때.
  static bool _lineDone(ApprovalStep before, ApprovalStep after) =>
      before.state == ApprovalStepState.done &&
      after.state != ApprovalStepState.upcoming;
}

class _StepColumn extends StatelessWidget {
  const new({
    required this.step,
    required this.number,
    required this.leftLine,
    required this.rightLine,
  });

  final ApprovalStep step;
  final int number;

  /// 왼쪽 · 오른쪽 이웃과 잇는 선 — `null` 이면 선이 없고, 값은 "진한 선인가" 다.
  final bool? leftLine;
  final bool? rightLine;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final caption = step.caption;
    final spoken = [
      step.label,
      switch (step.state) {
        ApprovalStepState.done => '완료',
        ApprovalStepState.current => '진행 중',
        ApprovalStepState.upcoming => '아직',
        ApprovalStepState.rejected => '거절됨',
      },
      if (caption != null && caption != '진행 중') caption,
    ].join(', ');

    return Semantics(
      container: true,
      label: spoken,
      excludeSemantics: true,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _Line(done: leftLine)),
              _Dot(state: step.state, number: number),
              Expanded(child: _Line(done: rightLine)),
            ],
          ),
          const SizedBox(height: BaraedaSpacing.space2),
          Text(
            step.label,
            textAlign: TextAlign.center,
            style: BaraedaTypography.caption.copyWith(
              fontWeight: step.state == ApprovalStepState.upcoming
                  ? BaraedaFontWeight.regular
                  : BaraedaFontWeight.bold,
              color: switch (step.state) {
                ApprovalStepState.rejected => colors.statusMissed,
                ApprovalStepState.upcoming => colors.textTertiary,
                _ => colors.textPrimary,
              },
              height: 1.3,
            ),
          ),
          if (caption != null)
            Text(
              caption,
              textAlign: TextAlign.center,
              style: BaraedaTypography.caption.copyWith(
                color: colors.textSecondary,
                height: 1.3,
              ),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const new({required this.done});

  final bool? done;

  @override
  Widget build(BuildContext context) {
    if (done == null) return const SizedBox(height: 2);
    return SizedBox(
      height: 2,
      child: ColoredBox(
        color: done!
            ? context.colors.accentPrimary
            : context.colors.borderDefault,
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const new({required this.state, required this.number});

  final ApprovalStepState state;
  final int number;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // (면 색, 테두리 색, 아이콘 이름 — 없으면 번호, 표시 색)
    final (fill, line, icon, markColor) = switch (state) {
      ApprovalStepState.done => (
        colors.accentPrimary,
        colors.accentPrimary,
        'check',
        colors.textInverse,
      ),
      ApprovalStepState.current => (
        colors.surfaceCard,
        colors.accentPrimary,
        null,
        colors.textPrimary,
      ),
      ApprovalStepState.upcoming => (
        colors.surfaceCard,
        colors.borderDefault,
        null,
        colors.textTertiary,
      ),
      ApprovalStepState.rejected => (
        colors.surfaceCard,
        colors.statusMissed,
        'x',
        colors.statusMissed,
      ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: line, width: 2),
      ),
      child: SizedBox(
        width: 28,
        height: 28,
        child: Center(
          child: icon == null
              ? Text(
                  '$number',
                  style: BaraedaTypography.caption.copyWith(
                    color: markColor,
                    fontWeight: BaraedaFontWeight.bold,
                    height: 1,
                  ),
                )
              : BaraedaIcon(icon, size: 16, color: markColor),
        ),
      ),
    );
  }
}
