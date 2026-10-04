import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/ui/confirm_dialog.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';

/// OfflineQueueScreen — 오프라인 큐 조회·수동 재전송 (API_SPEC §1.7, M-06,
/// UF-E-07).
///
/// 낙관적 UI 를 두지 않는다(§1.9) — 큐에 쌓인 요청은 서버 2xx 를 받기 전까지
/// 계속 "처리되지 않았습니다 · 대기 중" 으로 보여준다.
///
/// 이 화면의 버튼은 **수동** 재전송이다 — 자동 재생은 `OfflineQueueAutoSync`
/// (주기)와 `OfflineQueueRepository.sendOrQueue`(다음 쓰기 직전)가 맡으므로,
/// 이 화면을 한 번도 열지 않아도 복구 후 큐는 비워진다(M-06).
class OfflineQueueScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<OfflineQueueScreen> createState() => _OfflineQueueScreenState();
}

class _OfflineQueueScreenState extends ConsumerState<OfflineQueueScreen> {
  bool _replaying = false;
  String? _resultMessage;

  /// 재시도 버튼 — `replayPending()` 은 성공·재시도 불가를 이미 큐에서
  /// 제거해 반환하므로, 여기서는 요약 문구만 만들고 목록을 다시 읽는다.
  Future<void> _replay() async {
    setState(() {
      _replaying = true;
      _resultMessage = null;
    });
    // 예외로 끝나도 버튼이 영구히 잠기지 않게 한다(F06-15).
    String message;
    try {
      final result = await ref
          .read(offlineQueueRepositoryProvider)
          .replayPending();
      message = _describeResult(result);
    } on Object {
      message = '재시도를 완료하지 못했습니다';
    }
    if (!mounted) return;
    setState(() {
      _replaying = false;
      _resultMessage = message;
    });
    ref.invalidate(pendingRequestsProvider);
  }

  /// 잘못 눌러 쌓인 건을 큐에서 지운다 — 서버에 아직 반영되지 않은 처리를 버리는 일이라 한 번 묻는다.
  Future<void> _cancel(PendingRequestSummary item) async {
    final confirmed = await confirmAction(
      context,
      title: '${item.description}을(를) 삭제할까요?',
      body: '서버에 아직 반영되지 않았습니다. 삭제하면 이 처리는 보내지지 않습니다',
      confirmLabel: '삭제',
    );
    if (!confirmed || !mounted) return;
    final container = ProviderScope.containerOf(context);
    await ref.read(offlineQueueRepositoryProvider).cancel(item.id);
    container.invalidate(pendingRequestsProvider);
  }

  String _describeResult(ReplayResult result) {
    final parts = <String>[
      if (result.succeeded > 0) '${result.succeeded}건 처리됨',
      if (result.stillPending > 0) '${result.stillPending}건 대기 중',
      if (result.droppedPermanently > 0)
        '${result.droppedPermanently}건 재시도 불가로 제외',
      if (result.failedPermanently > 0)
        '${result.failedPermanently}건 전송 실패(서버가 계속 받지 못함)',
    ];
    if (parts.isEmpty) return '대기 중인 요청이 없습니다';
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final pendingAsync = ref.watch(pendingRequestsProvider);
    return Scaffold(
      appBar: const ManagerHeader(title: '대기열'),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(pendingRequestsProvider.future),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_resultMessage != null) ...[
              AlertBanner(tone: AlertTone.boarded, body: _resultMessage),
              const SizedBox(height: 12),
            ],
            BaraedaButton(
              label: '재시도',
              size: BaraedaButtonSize.lg,
              block: true,
              onPressed: _replaying ? null : _replay,
            ),
            const SizedBox(height: 20),
            pendingAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) =>
                  WordWrapText('대기열을 불러오지 못했습니다: ${describeError(error)}'),
              data: _buildList,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<PendingRequestSummary> items) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: 'clock',
        title: '대기 중인 요청이 없습니다',
        body: '네트워크 장애로 못 보낸 요청은 여기에 쌓입니다',
      );
    }
    // 카드가 문구 길이대로 줄어 가운데에 뜨지 않게 전체 폭으로 편다(`Ruling 592` 와 같은 처리).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items) ...[
          _buildListItem(item),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  /// 처리 이름에 학생 이름을 덧붙인다(M2-03) — 페이로드에 이름이 없어, 이미 받아 둔 명단(홈·명단 화면이 채운
  /// 캐시)에서 같은 회차·같은 승차 기록을 찾는다. 명단을 새로 받지 않고(오프라인일 수 있다), 못 찾으면 이름 없이 둔다.
  String _titleOf(PendingRequestSummary item) {
    final match = RegExp(r'^/runs/([^/]+)/riders/([^/]+)$').firstMatch(
      item.endpoint,
    );
    if (match == null || !ref.exists(rosterProvider)) return item.description;
    final roster = ref.read(rosterProvider).value;
    if (roster == null || roster.runId != match[1]) return item.description;
    for (final stop in roster.stops) {
      for (final student in stop.students) {
        if (student.riderId == match[2]) {
          return '${item.description} · ${student.name}';
        }
      }
    }
    return item.description;
  }

  Widget _buildListItem(PendingRequestSummary item) {
    return BaraedaCard(
      accent: BaraedaStatus.missed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _titleOf(item),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(DateFormat('MM/dd HH:mm:ss').format(item.createdAt.toLocal())),
          const SizedBox(height: 4),
          // 서버가 5xx 를 되풀이해 재생에서 뺀 행은 더 기다리지 않는다 — 보내지 못했음을 알리고 사용자가 정리한다.
          WordWrapText(
            item.failed
                ? '전송 실패 · 서버가 계속 받지 못했습니다. 삭제한 뒤 다시 처리해 주세요'
                : '처리되지 않았습니다 · 대기 중',
          ),
          const SizedBox(height: 8),
          BaraedaButton(
            label: '삭제',
            size: BaraedaButtonSize.sm,
            variant: BaraedaButtonVariant.ghost,
            onPressed: () => unawaited(_cancel(item)),
          ),
        ],
      ),
    );
  }
}
