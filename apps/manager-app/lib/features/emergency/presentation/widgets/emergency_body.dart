import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/ui/bottom_action_bar.dart';
import 'package:manager_app/core/ui/limited_text_controller.dart';
import 'package:manager_app/features/emergency/domain/models/emergency_raise_result.dart';
import 'package:manager_app/features/emergency/domain/models/emergency_type.dart';
import 'package:manager_app/features/emergency/presentation/emergency_providers.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_acked_view.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_failed_view.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_form.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_history.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_sent_view.dart';
import 'package:manager_app/features/offline_queue/domain/models/pending_request_summary.dart';

/// 큐에서 아직 안 나간 비상 신고 가운데 가장 나중 것 — 이 화면에서 누른 것뿐 아니라 앞서 쌓인 것도 센다.
/// 영구 실패로 굳은 행(`failed`)은 "계속 다시 보내는 중" 이 아니라 세지 않는다(Ruling 616).
PendingRequestSummary? latestUnsentEmergency(
  List<PendingRequestSummary>? pending,
) {
  if (pending == null) return null;
  PendingRequestSummary? latest;
  for (final request in pending) {
    if (!request.isEmergency || request.failed) continue;
    if (latest == null || request.createdAt.isAfter(latest.createdAt)) {
      latest = request;
    }
  }
  return latest;
}

/// 비상 화면 본문 — 상태에 맞는 내용(작성 · 발송 뒤 · 확인됨 · 전송 실패) ·
/// 오늘 보낸 이력 · 아래 단추 줄.
class EmergencyBody extends ConsumerWidget {
  const new({
    required this.unsent,
    required this.failed,
    required this.composing,
    required this.lastRaised,
    required this.lastRaisedType,
    required this.queuedAt,
    required this.queuedType,
    required this.type,
    required this.errorMessage,
    required this.cancelErrorMessage,
    required this.cancelingId,
    required this.submitting,
    required this.memoController,
    required this.onTypeChanged,
    required this.onSubmit,
    required this.onResend,
    required this.onCancel,
    super.key,
  });

  final PendingRequestSummary? unsent;
  final bool failed;
  final bool composing;
  final EmergencyRaiseResult? lastRaised;
  final EmergencyType? lastRaisedType;
  final DateTime? queuedAt;
  final EmergencyType? queuedType;
  final EmergencyType type;
  final String? errorMessage;
  final String? cancelErrorMessage;
  final String? cancelingId;
  final bool submitting;
  final LimitedTextController memoController;
  final ValueChanged<EmergencyType> onTypeChanged;
  final VoidCallback onSubmit;
  final VoidCallback onResend;
  final ValueChanged<String> onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(emergencyListProvider);
    // 위젯 안에서 `DateTime.now()` 를 직접 부르지 않는다
    // (CONVENTIONS_FLUTTER.md §9, 이월 11) — 취소 가능 창 판정에 쓴다.
    final now = ref.watch(clockProvider).now();
    final raised = composing ? null : lastRaised;
    final focus = raised == null
        ? null
        : listAsync.value?.items
              .where((item) => item.emergencyId == raised.emergencyId)
              .firstOrNull;

    final Widget content;
    final List<Widget> footer;
    if (failed) {
      content = EmergencyFailedView(
        unsent: unsent,
        queuedType: queuedType,
        queuedAt: queuedAt,
      );
      footer = [_ResendButton(onPressed: onResend)];
    } else if (raised != null) {
      content = focus != null && focus.acked
          ? EmergencyAckedView(
              item: focus,
              now: now,
              cancelErrorMessage: cancelErrorMessage,
              canceling: cancelingId == focus.emergencyId,
              onCancel: () => onCancel(focus.emergencyId),
            )
          : EmergencySentView(
              raised: raised,
              typeLabel: lastRaisedType?.label ?? '비상',
              cancelErrorMessage: cancelErrorMessage,
              canceling: cancelingId == raised.emergencyId,
              onCancel: () => onCancel(raised.emergencyId),
            );
      footer = focus != null && focus.acked
          ? const []
          : [_ResendButton(onPressed: onResend)];
    } else {
      content = EmergencyForm(
        type: type,
        errorMessage: errorMessage,
        submitting: submitting,
        memoController: memoController,
        onTypeChanged: onTypeChanged,
      );
      footer = [_SendButton(submitting: submitting, onPressed: onSubmit)];
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(emergencyListProvider.future),
            // 내용이 길지 않아 한꺼번에 만든다 — 화면 밖 이력 카드도 위젯 시험이 바로 찾는다.
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  content,
                  if (!failed) ...[
                    const SizedBox(height: 24),
                    EmergencyHistory(
                      listAsync: listAsync,
                      now: now,
                      excludeId: raised?.emergencyId,
                      cancelErrorMessage: lastRaised == null
                          ? cancelErrorMessage
                          : null,
                      cancelingId: cancelingId,
                      onCancel: onCancel,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (footer.isNotEmpty) BottomActionBar(children: footer),
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  const new({required this.submitting, required this.onPressed});

  final bool submitting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return BaraedaButton(
      label: '비상 알림 보내기',
      icon: 'triangle-alert',
      variant: BaraedaButtonVariant.danger,
      size: BaraedaButtonSize.xl,
      block: true,
      onPressed: submitting ? null : onPressed,
    );
  }
}

/// 상황이 바뀌면 같은 화면에서 다시 보낸다 — 지우기 어려운 빨간 면이 아니라 테두리 단추.
class _ResendButton extends StatelessWidget {
  const new({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return BaraedaButton(
      label: '새 상황으로 다시 보내기',
      icon: 'triangle-alert',
      variant: BaraedaButtonVariant.dangerOutline,
      block: true,
      onPressed: onPressed,
    );
  }
}
