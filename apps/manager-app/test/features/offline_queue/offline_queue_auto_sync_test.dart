import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/domain/offline_queue_repository.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_auto_sync.dart';

/// 재생 횟수만 세는 대역 — 한 번 재생하면 큐가 빈다.
class _FakeQueue implements OfflineQueueRepository {
  @override
  Future<void> clear() async {}

  @override
  Future<void> cancel(int id) async {}

  int pendingCount = 2;
  int replays = 0;

  @override
  Future<List<PendingRequestSummary>> fetchPending() async => List.generate(
    pendingCount,
    (index) => PendingRequestSummary(
      id: index,
      endpoint: '/runs/1/riders/$index',
      method: 'PATCH',
      payload: '{}',
      createdAt: DateTime(2026, 9, 21),
    ),
  );

  @override
  Future<ReplayResult> replayPending() async {
    replays++;
    final sent = pendingCount;
    pendingCount = 0;
    return ReplayResult(
      succeeded: sent,
      stillPending: 0,
      droppedPermanently: 0,
    );
  }

  @override
  Future<SendOutcome<T>> sendOrQueue<T>({
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
    required Future<T> Function() send,
  }) => throw UnimplementedError('이 위젯은 sendOrQueue 를 부르지 않는다');
}

Widget _harness(_FakeQueue queue, {UserRole? role}) => ProviderScope(
  overrides: [
    offlineQueueRepositoryProvider.overrideWithValue(queue),
    currentUserRoleProvider.overrideWith((ref) => role),
  ],
  child: const MaterialApp(
    home: OfflineQueueAutoSync(child: SizedBox.shrink()),
  ),
);

void main() {
  // M-06 은 "복구 시 **자동** 동기화" 를 요구한다 — 큐 화면의 재시도 버튼만
  // 있으면, 동승자가 두절 구간에서 처리한 승하차가 복구 후에도 아무도 그
  // 화면을 열지 않는 한 영영 서버에 닿지 않는다.
  testWidgets('앱이 떠 있는 동안 주기가 지나면 큐를 자동으로 재생한다', (tester) async {
    final queue = _FakeQueue();
    await tester.pumpWidget(_harness(queue, role: UserRole.escort));
    expect(queue.replays, 0, reason: '마운트만으로 재생하지 않는다');

    await tester.pump(OfflineQueueAutoSync.interval);
    await tester.pump();
    expect(queue.replays, 1);

    // 큐가 비었으면 다음 주기는 네트워크를 건드리지 않는다.
    await tester.pump(OfflineQueueAutoSync.interval);
    await tester.pump();
    expect(queue.replays, 1);
  });

  // 로그인 전에 재생하면 토큰이 없어 401 이 오고, 재생 규칙상 401 은
  // "재시도해도 같은 결과" 라 큐에서 **영구 제거**된다 — 쌓아 둔 승하차
  // 처리가 통째로 사라진다.
  testWidgets('로그인 전에는 자동 재생하지 않는다', (tester) async {
    final queue = _FakeQueue();
    await tester.pumpWidget(_harness(queue));

    await tester.pump(OfflineQueueAutoSync.interval);
    await tester.pump();

    expect(queue.replays, 0);
  });
}
