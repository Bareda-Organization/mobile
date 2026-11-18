import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/runs/presentation/run_display.dart';
import 'package:parent_app/core/ui/format_date_time.dart';
import 'package:parent_app/features/schedule/presentation/schedule_providers.dart';

/// 제출 성공 때 영수증에 쓸 값 — 폼이 비워지기 전에 담아 둔다.
class ChangeRequestReceiptData {
  const new({
    required this.pendingApproval,
    required this.type,
    this.deadlineAt,
    this.run,
    this.originalStop,
    this.address,
    this.reason,
  });

  /// 접수 직후의 폼 값에서 영수증 값을 만든다 — 빈 주소 · 사유는 영수증에서 뺀다.
  factory submitted({
    required bool pendingApproval,
    required DateTime? deadlineAt,
    required StudentRun? run,
    required ChangeRequestType type,
    required String address,
    required String reason,
  }) => ChangeRequestReceiptData(
    pendingApproval: pendingApproval,
    deadlineAt: deadlineAt,
    run: run == null
        ? null
        : '${run.direction.label} · ${formatClock(run.departTime)} 출발',
    originalStop: run?.stop.name,
    type: type,
    address: type == ChangeRequestType.relocate ? address : null,
    reason: reason.isEmpty ? null : reason,
  );

  final bool pendingApproval;
  final DateTime? deadlineAt;
  final String? run;
  final String? originalStop;
  final ChangeRequestType type;
  final String? address;
  final String? reason;
}

/// 제출 뒤 화면 — 무엇을 신청했는지 영수증으로 보여 주고, 승인 전에는 원래 승하차지로 버스가 온다는 말을 한다.
class ChangeRequestReceipt extends ConsumerWidget {
  const new({required this.receipt, super.key});

  final ChangeRequestReceiptData receipt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deadline = receipt.deadlineAt;
    final deadlineText = deadline == null
        ? '학원이 확인하면 알림으로 알려 드려요'
        : '마감 ${formatDateTime(deadline)} · 학원이 확인하면 알림으로 알려 드려요';
    return ListView(
      padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
      children: [
        AlertBanner(
          tone: receipt.pendingApproval ? AlertTone.moving : AlertTone.boarded,
          title: receipt.pendingApproval ? '승인 요청을 보냈어요' : '변경했어요',
          body: receipt.pendingApproval ? deadlineText : '바로 반영됐어요',
        ),
        const SizedBox(height: BaraedaSpacing.space4),
        BaraedaReceiptCard(
          title: '신청 내용',
          rows: [
            if (receipt.run != null) BaraedaReceiptRow('회차', receipt.run!),
            BaraedaReceiptRow(
              '변경',
              receipt.type == ChangeRequestType.cancel ? '탑승 취소' : '승하차지 변경',
            ),
            if (receipt.address != null)
              BaraedaReceiptRow('변경할 주소', receipt.address!),
            if (receipt.reason != null)
              BaraedaReceiptRow('사유', receipt.reason!),
          ],
        ),
        if (receipt.pendingApproval) ...[
          const SizedBox(height: BaraedaSpacing.space3),
          Text(
            [
              if (receipt.originalStop != null)
                '승인되기 전까지는 원래 승하차지(${receipt.originalStop})로 버스가 와요.',
              if (deadline != null)
                '${formatClock(deadline)} 까지 승인되지 않으면 자동으로 반려돼요.',
            ].join(' '),
            style: BaraedaTypography.body.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: BaraedaSpacing.space6),
        BaraedaButton(
          label: '일정으로 돌아가기',
          block: true,
          onPressed: () => context.go(AppRoutes.schedule),
        ),
        const SizedBox(height: BaraedaSpacing.space2),
        BaraedaButton(
          label: '신청 이력 보기',
          block: true,
          variant: BaraedaButtonVariant.ghost,
          // 일정 탭이 신청 이력 자리까지 내려가 있게 한다 — 안 그러면 위 단추와 같은 곳(맨 위)으로 가는 단추가 된다.
          onPressed: () {
            ref.read(scheduleShowHistoryProvider.notifier).state = true;
            context.go(AppRoutes.schedule);
          },
        ),
      ],
    );
  }
}
