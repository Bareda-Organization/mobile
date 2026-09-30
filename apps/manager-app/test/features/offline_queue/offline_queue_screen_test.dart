import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/domain/offline_queue_repository.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_screen.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';

/// 테스트 전용 대역 — 이 화면은 `sendOrQueue` 를 직접 부르지 않으므로(즉시
/// 전송·재생 경로는 각 기능 화면에서 이미 검증됨) 여기서는 미구현으로 두고,
/// 화면이 실제로 쓰는 `fetchPending`·`replayPending` 만 결과를 주입한다.
class _FakeOfflineQueueRepository implements OfflineQueueRepository {
  _FakeOfflineQueueRepository({
    required List<PendingRequestSummary> pending,
    this.replayResult,
    this.replayError,
  })
    // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
    // 쓴다(OfflineQueueRepositoryImpl 과 같은 이유 — replayPending 이 재대입
    // 해야 해서 field 를 밖에서 직접 못 건드리게 막아 둔다).
    // ignore: prefer_initializing_formals
    : _pending = pending;

  List<PendingRequestSummary> _pending;
  final ReplayResult? replayResult;
  final Exception? replayError;

  @override
  Future<void> clear() async {}

  final canceledIds = <int>[];

  @override
  Future<void> cancel(int id) async {
    canceledIds.add(id);
    _pending = [
      for (final item in _pending)
        if (item.id != id) item,
    ];
  }

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
    if (replayError != null) throw replayError!;
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

RosterResponse _rosterOf(String runId) => RosterResponse(
  runId: runId,
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  counts: const RosterCounts(boarded: 0, waiting: 1, noShow: 0, absentN: 0),
  stops: [
    const RosterStop(
      stopId: 'stop-1',
      seq: 1,
      name: '정류장1',
      students: [
        RosterStudent(
          riderId: 'rider-1',
          studentId: 'student-1',
          name: '김철수',
          photoUrl: null,
          guardianPhone: null,
          canGoAlone: false,
          status: RiderStatus.waiting,
        ),
      ],
    ),
  ],
);

PendingRequestSummary _riderRequest() => PendingRequestSummary(
  id: 1,
  endpoint: '/runs/run-1/riders/rider-1',
  method: 'PATCH',
  payload: '{"status":"no_show","client_key":"K"}',
  createdAt: DateTime(2026, 9, 12, 10),
);

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
          endpoint: '/runs/run-1/riders/rider-1',
          method: 'PATCH',
          payload: '{"status":"no_show","client_key":"K"}',
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

    // F06-15 — 개발용 문자열(PATCH /runs/…)이 아니라 무슨 처리인지 알아볼 수 있어야 한다.
    expect(find.text('미승차 처리'), findsOneWidget);
    expect(find.textContaining('PATCH'), findsNothing);
    expect(find.text('처리되지 않았습니다 · 대기 중'), findsOneWidget);
  });

  testWidgets('재시도를 누르면 처리 결과 요약을 보여준다', (tester) async {
    final fakeRepo = _FakeOfflineQueueRepository(
      pending: [
        PendingRequestSummary(
          id: 1,
          endpoint: '/runs/run-1/emergency',
          method: 'POST',
          payload: '{"type":"accident","client_key":"K"}',
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
          endpoint: '/runs/run-1/emergency',
          method: 'POST',
          payload: '{"type":"accident","client_key":"K"}',
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
    expect(find.text('비상 신고 · 사고'), findsOneWidget);

    await tester.tap(find.text('재시도'));
    await tester.pumpAndSettle();

    expect(find.text('비상 신고 · 사고'), findsNothing);
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

  // F06-15 — 잘못 눌러 쌓인 건을 지울 수단이 없었다.
  testWidgets('대기 항목의 [삭제] 를 확인하면 그 건만 큐에서 지운다', (tester) async {
    final fakeRepo = _FakeOfflineQueueRepository(
      pending: [
        PendingRequestSummary(
          id: 1,
          endpoint: '/runs/run-1/riders/rider-1',
          method: 'PATCH',
          payload: '{"status":"boarded"}',
          createdAt: DateTime(2026, 9, 12, 10),
        ),
        PendingRequestSummary(
          id: 2,
          endpoint: '/runs/run-1/riders/rider-2',
          method: 'PATCH',
          payload: '{"status":"alighted"}',
          createdAt: DateTime(2026, 9, 12, 10, 1),
        ),
      ],
    );
    await tester.pumpWidget(
      _wrap(const OfflineQueueScreen(), [
        offlineQueueRepositoryProvider.overrideWithValue(fakeRepo),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('탑승 처리'), findsOneWidget);
    expect(find.text('하차 처리'), findsOneWidget);

    await tester.tap(find.text('삭제').first);
    await tester.pumpAndSettle();
    // 서버에 아직 반영되지 않은 처리를 버리는 일이라 한 번 묻는다.
    await tester.tap(
      find.descendant(
        of: find.byType(BaraedaDialog),
        matching: find.text('삭제'),
      ),
    );
    await tester.pumpAndSettle();

    expect(fakeRepo.canceledIds, [1]);
    expect(find.text('탑승 처리'), findsNothing);
    expect(find.text('하차 처리'), findsOneWidget);
  });

  // F06-15 — 재시도가 예외로 끝나면 버튼이 영구히 잠겼다.
  testWidgets('재시도가 예외로 끝나도 버튼이 다시 눌린다', (tester) async {
    final fakeRepo = _FakeOfflineQueueRepository(
      pending: const [],
      replayError: Exception('저장소 오류'),
    );
    await tester.pumpWidget(
      _wrap(const OfflineQueueScreen(), [
        offlineQueueRepositoryProvider.overrideWithValue(fakeRepo),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('재시도'));
    await tester.pumpAndSettle();

    expect(find.text('재시도를 완료하지 못했습니다'), findsOneWidget);
    final button = tester.widget<BaraedaButton>(
      find.widgetWithText(BaraedaButton, '재시도'),
    );
    expect(button.onPressed, isNotNull);
  });

  // M2-03(F06-15 나머지) — 페이로드에 이름이 없어 명단 캐시에서 찾는다. 못 찾으면 지금 표기 그대로다.
  testWidgets('받아 둔 명단에 그 학생이 있으면 행에 학생 이름을 함께 보여준다', (tester) async {
    await tester.pumpWidget(
      _wrap(const OfflineQueueScreen(), [
        offlineQueueRepositoryProvider.overrideWithValue(
          _FakeOfflineQueueRepository(pending: [_riderRequest()]),
        ),
        selectedRunIdProvider.overrideWith((ref) => 'run-1'),
        rosterProvider.overrideWith((ref) async => _rosterOf('run-1')),
      ]),
    );
    // 홈·명단 화면이 이미 받아 둔 캐시를 흉내 낸다.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OfflineQueueScreen)),
    );
    await container.read(rosterProvider.future);
    container.invalidate(pendingRequestsProvider);
    await tester.pumpAndSettle();

    expect(find.text('미승차 처리 · 김철수'), findsOneWidget);
  });

  testWidgets('받아 둔 명단이 다른 회차면 이름 없이 지금 표기 그대로 보여준다', (tester) async {
    await tester.pumpWidget(
      _wrap(const OfflineQueueScreen(), [
        offlineQueueRepositoryProvider.overrideWithValue(
          _FakeOfflineQueueRepository(pending: [_riderRequest()]),
        ),
        selectedRunIdProvider.overrideWith((ref) => 'run-2'),
        rosterProvider.overrideWith((ref) async => _rosterOf('run-2')),
      ]),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OfflineQueueScreen)),
    );
    await container.read(rosterProvider.future);
    container.invalidate(pendingRequestsProvider);
    await tester.pumpAndSettle();

    expect(find.text('미승차 처리'), findsOneWidget);
  });
}
