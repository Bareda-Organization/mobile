import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/features/emergency/domain/models/emergency_item.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_time_label.dart';

/// 오늘 보낸 비상 알림 목록 — 제목 · 건수 · 취소 실패 안내 · 이력 카드.
///
/// [excludeId] 알림의 취소 단추는 그리지 않는다 — 방금 보낸 알림의 취소는 위 카드가 맡는다.
class EmergencyHistory extends StatelessWidget {
  const new({
    required this.listAsync,
    required this.now,
    required this.excludeId,
    required this.cancelErrorMessage,
    required this.cancelingId,
    required this.onCancel,
    super.key,
  });

  final AsyncValue<EmergencyListResponse> listAsync;
  final DateTime now;
  final String? excludeId;

  /// 이 목록 위에 띄울 취소 실패 안내 — 없으면 `null`.
  final String? cancelErrorMessage;
  final String? cancelingId;
  final ValueChanged<String> onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '오늘 보낸 비상 알림',
                style: BaraedaTypography.title.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            listAsync.maybeWhen(
              data: (list) => Text(
                '${list.items.length}건',
                style: BaraedaTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (cancelErrorMessage != null) ...[
          AlertBanner(tone: AlertTone.missed, body: cancelErrorMessage),
          const SizedBox(height: 12),
        ],
        listAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) =>
              WordWrapText('이력을 불러오지 못했어요: ${describeError(error)}'),
          data: (list) => _HistoryList(
            items: list.items,
            now: now,
            excludeId: excludeId,
            cancelingId: cancelingId,
            onCancel: onCancel,
          ),
        ),
      ],
    );
  }
}

class _HistoryList extends StatelessWidget {
  const new({
    required this.items,
    required this.now,
    required this.excludeId,
    required this.cancelingId,
    required this.onCancel,
  });

  final List<EmergencyItem> items;
  final DateTime now;
  final String? excludeId;
  final String? cancelingId;
  final ValueChanged<String> onCancel;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: 'bell',
        title: '발신한 비상 알림이 없어요',
        body: '비상 상황이 생기면 위에서 바로 보낼 수 있어요',
      );
    }
    // stretch 가 없으면 카드가 내용 폭으로 줄어 가운데에 뜬다.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items) ...[
          _HistoryItem(
            item: item,
            now: now,
            excludeId: excludeId,
            cancelingId: cancelingId,
            onCancel: onCancel,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _HistoryItem extends StatelessWidget {
  const new({
    required this.item,
    required this.now,
    required this.excludeId,
    required this.cancelingId,
    required this.onCancel,
  });

  final EmergencyItem item;
  final DateTime now;
  final String? excludeId;
  final String? cancelingId;
  final ValueChanged<String> onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canceled = item.canceledAt != null;
    final status = canceled
        ? BaraedaStatus.idle
        : item.acked
        ? BaraedaStatus.boarded
        : BaraedaStatus.waiting;
    // 방금 보낸 알림의 취소는 위 카드가 맡는다 — 같은 알림에 취소 단추가 둘이 되지 않게 한다.
    final canCancel =
        !canceled &&
        now.isBefore(item.cancelableUntil) &&
        item.emergencyId != excludeId;
    return BaraedaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceSunken,
                  borderRadius: BorderRadius.circular(BaraedaRadius.control),
                ),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: BaraedaIcon(
                      'triangle-alert',
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: BaraedaSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.type.label} · '
                      '${emergencyTimeLabel(item.raisedAt)}',
                      style: BaraedaTypography.body.copyWith(
                        color: colors.textPrimary,
                        fontWeight: BaraedaFontWeight.bold,
                      ),
                    ),
                    Text(
                      _statusLabelOf(item, canceled),
                      style: BaraedaTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              BaraedaStatusPill(
                status: status,
                label: canceled
                    ? '취소됨'
                    : item.acked
                    ? '확인함'
                    : '확인 대기',
              ),
            ],
          ),
          if (canCancel) ...[
            const SizedBox(height: 8),
            BaraedaButton(
              label: '취소',
              variant: BaraedaButtonVariant.dangerOutline,
              size: BaraedaButtonSize.sm,
              onPressed: cancelingId == item.emergencyId
                  ? null
                  : () => onCancel(item.emergencyId),
            ),
          ],
        ],
      ),
    );
  }
}

String _statusLabelOf(EmergencyItem item, bool canceled) {
  if (canceled) return '취소됨';
  if (item.acked) {
    final byName = item.ackedByName;
    return (byName == null || byName.isEmpty) ? '확인됨' : '$byName 님이 확인함';
  }
  return '확인 대기 중';
}
