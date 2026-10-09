import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/change_requests/presentation/change_request_providers.dart';
import 'package:parent_app/core/time/service_date.dart';

/// 일정 탭 맨 아래 신청 이력(§3.9) — 종류·대상 회차·신청·처리 시각과 상태 칩, 반려 사유.
///
/// 대상 회차(`오늘 하원`)는 서버가 방향·날짜를 줄 때만 붙인다(`Ruling 824`) — 안 주면 종류만 쓴다.
class ChangeRequestHistory extends ConsumerWidget {
  const new({required this.studentId, super.key});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(changeRequestsProvider(studentId));
    final today = koreaServiceDate(ref.watch(clockProvider).now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: BaraedaSpacing.space2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('신청 이력', style: BaraedaTypography.h3),
              if (requestsAsync.value case final page?
                  when page.items.isNotEmpty)
                Text(
                  '최근 ${page.items.length}건',
                  style: BaraedaTypography.caption.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        requestsAsync.when(
          loading: () => const BaraedaSkeletonList(count: 2),
          error: (error, stack) => AlertBanner(
            tone: AlertTone.missed,
            body: '신청 이력을 불러오지 못했어요',
            inlineAction: true,
            action: BaraedaButton(
              label: '다시 시도',
              size: BaraedaButtonSize.sm,
              variant: BaraedaButtonVariant.secondary,
              onPressed: () =>
                  ref.invalidate(changeRequestsProvider(studentId)),
            ),
          ),
          data: (page) => page.items.isEmpty
              ? const EmptyState(title: '신청 이력이 없어요')
              : BaraedaListGroup(
                  children: [for (final item in page.items) _row(item, today)],
                ),
        ),
      ],
    );
  }
}

Widget _row(ChangeRequest item, DateTime today) {
  final chip = historyChip(item.status);
  return BaraedaListRow(
    leadingIcon: item.type == ChangeRequestType.cancel ? 'x' : 'route',
    title: historyTitle(item, today),
    subtitle: historySubtitle(item),
    wrapSubtitleByWord: true,
    trailing: BaraedaStatusPill(status: chip.status, label: chip.label),
  );
}

/// `탑승 취소 · 오늘 하원` — 방향·날짜를 서버가 줬을 때만 뒤를 붙인다.
String historyTitle(ChangeRequest item, DateTime today) {
  final kind = item.type == ChangeRequestType.cancel ? '탑승 취소' : '승하차지 변경';
  final date = item.serviceDate;
  final direction = item.direction;
  if (date == null || direction == null) return kind;
  final days = date.difference(today).inDays;
  final dayWord = switch (days) {
    0 => '오늘',
    1 => '내일',
    -1 => '어제',
    _ => '${date.month}월 ${date.day}일',
  };
  return '$kind · $dayWord ${direction.label}';
}

/// 신청·처리 시각 한 줄 + 사유가 있으면 둘째 줄.
String historySubtitle(ChangeRequest item) {
  final requested = item.requestedAt;
  final decided = item.decidedAt;
  final first = <String>[
    ?(requested == null ? null : '${_dateTime(requested)} 신청'),
    ?switch (item.status) {
      ChangeRequestStatus.approved when requested != null && decided != null =>
        decided.difference(requested).inMinutes < 1
            ? '바로 반영'
            : '${_sameDayTime(requested, decided)} 처리',
      ChangeRequestStatus.rejected when decided != null =>
        '${_sameDayTime(requested, decided)} 처리',
      ChangeRequestStatus.pending => '승인을 기다리고 있어요',
      _ => null,
    },
  ].join(' · ');
  final second = switch (item.status) {
    ChangeRequestStatus.rejected when item.rejectReason != null =>
      '반려: ${item.rejectReason}',
    ChangeRequestStatus.autoRejected => '출발 시각까지 승인되지 않아 자동으로 반려됐어요',
    _ => null,
  };
  return [if (first.isNotEmpty) first, ?second].join('\n');
}

({BaraedaStatus status, String label}) historyChip(
  ChangeRequestStatus status,
) => switch (status) {
  ChangeRequestStatus.pending => (status: BaraedaStatus.waiting, label: '대기'),
  ChangeRequestStatus.approved => (status: BaraedaStatus.boarded, label: '승인'),
  ChangeRequestStatus.rejected => (status: BaraedaStatus.missed, label: '반려'),
  ChangeRequestStatus.autoRejected => (
    status: BaraedaStatus.missed,
    label: '자동 반려',
  ),
};

String _two(int n) => n.toString().padLeft(2, '0');

String _dateTime(DateTime time) {
  final t = time.toLocal();
  return '${t.month}월 ${t.day}일 ${_two(t.hour)}:${_two(t.minute)}';
}

/// 신청과 같은 날 처리했으면 시각만, 다른 날이면 날짜까지.
String _sameDayTime(DateTime? requested, DateTime decided) {
  final d = decided.toLocal();
  final r = requested?.toLocal();
  final clock = '${_two(d.hour)}:${_two(d.minute)}';
  return r != null && r.year == d.year && r.month == d.month && r.day == d.day
      ? clock
      : '${d.month}월 ${d.day}일 $clock';
}
