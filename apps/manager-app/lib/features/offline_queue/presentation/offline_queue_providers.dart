import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';

/// 오프라인 큐 화면(`offline_queue_screen.dart`) 전용 provider — 대기 중인
/// 요청 목록.
///
/// 선택된 회차에 종속되지 않는다 — `OfflineQueueRepository.fetchPending` 은
/// runId 를 받지 않는다(큐는 기기 로컬에 쌓이는 저장소라 회차가 끝나거나
/// 바뀌어도 대기 중인 요청을 계속 보여줘야 한다).
final pendingRequestsProvider = FutureProvider<List<PendingRequestSummary>>((
  ref,
) {
  return ref.watch(offlineQueueRepositoryProvider).fetchPending();
});
