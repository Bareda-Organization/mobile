import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/domain/offline_queue_repository.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_screen.dart';

/// 테스트 전용 대역 — 이 화면은 `sendOrQueue` 를 직접 부르지 않으므로(즉시
/// 전송·재생 경로는 각 기능 화면에서 이미 검증됨) 여기서는 미구현으로 두고,
/// 화면이 실제로 쓰는 `fetchPending`·`replayPending` 만 결과를 주입한다.
class _FakeOfflineQueueRepository implements OfflineQueueRepository {
  _FakeOfflineQueueRepository({
    required List<PendingRequestSummary> pending,
    this.replayResult,
  })
    // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
    // 쓴다(OfflineQueueRepositoryImpl 과 같은 이유 — replayPending 이 재대입
    // 해야 해서 field 를 밖에서 직접 못 건드리게 막아 둔다).
    // ignore: prefer_initializing_formals
    : _pending = pending;

  List<PendingRequestSummary> _pending;
  final ReplayResult? replayResult;

  int fetchCallCount = 0;
  int replayCallCount = 0;

  @override
  Future<SendOutcome<T>> sendOrQueue<T>({
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
    required Future<T> Function() send,
  }) {
    throw UnimplementedError('이 화면은 sendOrQueue 를 직접 호출하지 않는다');
  }

  @override
  Future<List<PendingRequestSummary>> fetchPending() async {
    fetchCallCount++;
    return _pending;
  }

  @override
  Future<ReplayResult> replayPending() async {
    replayCallCount++;
    // 재시도 후 대기 목록이 비어야 "목록이 갱신됐다" 를 화면에서 검증할 수
    // 있다 — 실제 구현(OfflineQueueRepositoryImpl.replayPending)도 처리된
    // 행을 drift 테이블에서 지운다.
    _pending = const [];
    return replayResult!;
  }
}

Widget _wrap(Widget child, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('대기 중인 요청이 없으면 빈 상태를 보여준다', (tester) async {
    final fakeRepo = _FakeOfflineQueueRepository(pending: const []);
    await tester.pumpWidget(
      _wrap(const OfflineQueueScreen(), [
        offlineQueueRepositoryProvider.overrideWithValue(fakeRepo),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('대기 중인 요청이 없습니다'), findsOneWidget);
  });

  testWidgets('대기 중인 요청이 있으면 각 항목의 메서드·경로·대기 문구를 보여준다', (tester) async {
    final fakeRepo = _FakeOfflineQueueRepository(
      pending: [
        PendingRequestSummary(
          id: 1,
          endpoint: '/staff/runs/run-1/riders/rider-1/status',
          method: 'PATCH',
          createdAt: DateTime(2026, 9, 12, 10),
        ),
      ],
    );
    await tester.pumpWidget(
      _wrap(const OfflineQueueScreen(), [
        offlineQueueRepositoryProvider.overrideWithValue(fakeRepo),
      ]),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('PATCH /staff/runs/run-1/riders/rider-1/status'),
      findsOneWidget,
    );
    expect(find.text('처리되지 않았습니다 · 대기 중'), findsOneWidget);
  });

  testWidgets('재시도를 누르면 처리 결과 요약을 보여준다', (tester) async {
    final fakeRepo = _FakeOfflineQueueRepository(
      pending: [
        PendingRequestSummary(
          id: 1,
          endpoint: '/staff/emergencies',
          method: 'POST',
          createdAt: DateTime(2026, 9, 12, 10),
        ),
      ],
      replayResult: const ReplayResult(
        succeeded: 2,
        stillPending: 1,
        droppedPermanently: 0,
      ),
    );
    await tester.pumpWidget(
      _wrap(const OfflineQueueScreen(), [
        offlineQueueRepositoryProvider.overrideWithValue(fakeRepo),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('재시도'));
    await tester.pumpAndSettle();

    expect(find.text('2건 처리됨 · 1건 대기 중'), findsOneWidget);
    expect(fakeRepo.replayCallCount, 1);
  });

  testWidgets('재시도 후 목록을 다시 불러와 처리된 항목이 사라진다', (tester) async {
    final fakeRepo = _FakeOfflineQueueRepository(
      pending: [
        PendingRequestSummary(
          id: 1,
          endpoint: '/staff/emergencies',
          method: 'POST',
          createdAt: DateTime(2026, 9, 12, 10),
        ),
      ],
      replayResult: const ReplayResult(
        succeeded: 1,
        stillPending: 0,
        droppedPermanently: 0,
      ),
    );
    await tester.pumpWidget(
      _wrap(const OfflineQueueScreen(), [
        offlineQueueRepositoryProvider.overrideWithValue(fakeRepo),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('POST /staff/emergencies'), findsOneWidget);

    await tester.tap(find.text('재시도'));
    await tester.pumpAndSettle();

    expect(find.text('POST /staff/emergencies'), findsNothing);
    expect(find.text('대기 중인 요청이 없습니다'), findsOneWidget);
    expect(fakeRepo.fetchCallCount, greaterThanOrEqualTo(2));
  });

  testWidgets('재시도 결과가 전부 0건이면 대기 요청 없음 안내를 보여준다', (tester) async {
    final fakeRepo = _FakeOfflineQueueRepository(
      pending: const [],
      replayResult: const ReplayResult(
        succeeded: 0,
        stillPending: 0,
        droppedPermanently: 0,
      ),
    );
    await tester.pumpWidget(
      _wrap(const OfflineQueueScreen(), [
        offlineQueueRepositoryProvider.overrideWithValue(fakeRepo),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('재시도'));
    await tester.pumpAndSettle();

    // 빈 상태(EmptyState) 제목과 배너 문구가 같은 문자열을 쓰므로 두 곳에서
    // 발견돼야 한다 — 배너가 새로 나타났다는 뜻이다.
    expect(find.text('대기 중인 요청이 없습니다'), findsNWidgets(2));
  });
}
