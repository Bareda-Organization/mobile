import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';

/// OfflineQueueScreen — 오프라인 큐 조회·수동 재전송 (API_SPEC §1.7, M-06,
/// UF-E-07).
///
/// 낙관적 UI 를 두지 않는다(§1.9) — 큐에 쌓인 요청은 서버 2xx 를 받기 전까지
/// 계속 "처리되지 않았습니다 · 대기 중" 으로 보여준다. 자동 폴링·재전송은
/// 두지 않는다(WS 도입 이후 F4 몫) — 재전송은 이 화면의 버튼을 눌렀을 때만
/// 일어난다.
class OfflineQueueScreen extends ConsumerStatefulWidget {
  const OfflineQueueScreen({super.key});

  @override
  ConsumerState<OfflineQueueScreen> createState() =>
      _OfflineQueueScreenState();
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
    final result = await ref
        .read(offlineQueueRepositoryProvider)
        .replayPending();
    if (!mounted) return;
    setState(() {
      _replaying = false;
      _resultMessage = _describeResult(result);
    });
    ref.invalidate(pendingRequestsProvider);
  }

  String _describeResult(ReplayResult result) {
    final parts = <String>[
      if (result.succeeded > 0) '${result.succeeded}건 처리됨',
      if (result.stillPending > 0) '${result.stillPending}건 대기 중',
      if (result.droppedPermanently > 0)
        '${result.droppedPermanently}건 재시도 불가로 제외',
    ];
    if (parts.isEmpty) return '대기 중인 요청이 없습니다';
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final pendingAsync = ref.watch(pendingRequestsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('오프라인 대기열')),
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
              error: (error, _) => Text('대기열을 불러오지 못했습니다: $error'),
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
        body: '네트워크 장애로 보내지 못한 요청이 있으면 여기에 쌓입니다',
      );
    }
    return Column(
      children: [
        for (final item in items) ...[
          _buildListItem(item),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildListItem(PendingRequestSummary item) {
    return BaraedaCard(
      accent: BaraedaStatus.missed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item.method} ${item.endpoint}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(DateFormat('MM/dd HH:mm:ss').format(item.createdAt)),
          const SizedBox(height: 4),
          const Text('처리되지 않았습니다 · 대기 중'),
        ],
      ),
    );
  }
}
