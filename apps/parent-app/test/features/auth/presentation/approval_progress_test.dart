import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/features/auth/presentation/widgets/approval_progress.dart';

/// 승인 대기 진행 막대(시안 `pending*`) — 상태가 단계 셋으로 어떻게 바뀌는지.
/// 학원이 확인한 시각은 응답에 없으므로(REPORT-MP §1.3) 어느 단계에도 그 시각을 달지 않는다.
void main() {
  final requestedAt = DateTime(2026, 10, 3, 9, 41);

  List<(String, ApprovalStepState, String?)> view(AccountStatus status) => [
    for (final step in approvalSteps(status, requestedAt))
      (step.label, step.state, step.caption),
  ];

  test('승인 대기 — 신청 접수는 끝났고 학원 확인이 진행 중이며 사용 시작은 아직이다', () {
    expect(view(AccountStatus.pending), [
      ('신청 접수', ApprovalStepState.done, '09:41'),
      ('학원 확인', ApprovalStepState.current, '진행 중'),
      ('사용 시작', ApprovalStepState.upcoming, null),
    ]);
  });

  test('거절 — 학원 확인까지 끝났고 마지막 단계가 "거절"로 바뀐다', () {
    expect(view(AccountStatus.rejected), [
      ('신청 접수', ApprovalStepState.done, '09:41'),
      ('학원 확인', ApprovalStepState.done, null),
      ('거절', ApprovalStepState.rejected, null),
    ]);
  });

  test('학원이 확인한 시각은 어느 단계에도 없다 — 시각 모양의 글자는 신청 접수 하나뿐이다', () {
    final timeLike = RegExp(r'^\d{2}:\d{2}$');
    for (final status in [AccountStatus.pending, AccountStatus.rejected]) {
      final withTime = [
        for (final step in approvalSteps(status, requestedAt))
          if (step.caption != null && timeLike.hasMatch(step.caption!))
            step.label,
      ];
      expect(withTime, ['신청 접수'], reason: '$status');
    }
  });

  test('승인이 끝난 계정이면 세 단계 모두 끝이다', () {
    final steps = approvalSteps(AccountStatus.active, requestedAt);
    expect([
      for (final step in steps) step.state,
    ], everyElement(ApprovalStepState.done));
  });
}
