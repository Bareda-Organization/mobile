import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';
import 'package:manager_app/features/roster/data/models/boarding_update_request.dart';
import 'package:manager_app/features/roster/data/models/rider_update_result.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/domain/roster_repository.dart';
import 'package:manager_app/features/roster/presentation/roster_screen.dart';

import '../../support/manager_run_fixture.dart';

/// 학생마다 응답을 붙잡아 둘 수 있는 가짜 명단 저장소 — 약한 신호에서 응답이 늦는 상황을 만든다.
/// 큐에 쌓인 것으로 답한 처리는 [queue] 에도 적어, 큐 목록 provider 가 같은 내용을 돌려주게 한다.
class _GatedRosterRepository implements RosterRepository {
  new(this.roster);

  final RosterResponse roster;

  /// 이 학생의 응답을 기다리게 한다 — 시험이 `complete` 할 때까지 요청이 끝나지 않는다.
  final Map<String, Completer<SendOutcome<RiderUpdateResult>>> gates = {};

  /// 이 학생에게는 통신 두절로 큐에 쌓인 것으로 답한다.
  final Set<String> queuedRiders = {};
  final List<PendingRequestSummary> queue = [];
  final List<String> calls = [];

  @override
  Future<RosterResponse> fetchRoster(String runId) async => roster;

  @override
  Future<SendOutcome<RiderUpdateResult>> updateRiderStatus({
    required String runId,
    required String riderId,
    required BoardingUpdateRequest request,
  }) async {
    calls.add('$riderId:${request.status.wireValue}');
    if (queuedRiders.contains(riderId)) {
      queue.add(
        PendingRequestSummary(
          id: queue.length + 1,
          endpoint: '/runs/$runId/riders/$riderId',
          method: 'PATCH',
          payload: '{"status":"${request.status.wireValue}"}',
          createdAt: DateTime(2026, 10, 1, 8),
        ),
      );
      return const Queued();
    }
    final gate = gates[riderId];
    if (gate != null) return await gate.future;
    return Sent(_result(riderId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('이 파일의 시험 대상이 아니다');
}

RiderUpdateResult _result(String riderId) => RiderUpdateResult(
  riderId: riderId,
  status: RiderStatus.boarded,
  changedAt: DateTime(2026, 10, 1, 8),
  stopSkipped: false,
);

RosterStudent _student(String riderId, String name) => RosterStudent(
  riderId: riderId,
  studentId: 's-$riderId',
  name: name,
  photoUrl: null,
  guardianPhone: null,
  canGoAlone: false,
  status: RiderStatus.waiting,
);

final _roster = RosterResponse(
  runId: 'run-1',
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  counts: const RosterCounts(boarded: 0, waiting: 2, noShow: 0, absentN: 0),
  stops: [
    RosterStop(
      stopId: 'stop-1',
      seq: 1,
      name: 'A정류장',
      students: [_student('r1', '김바래'), _student('r2', '이바래')],
    ),
  ],
);

void main() {
  late _GatedRosterRepository repository;

  Future<void> pumpRoster(
    WidgetTester tester, {
    List<PendingRequestSummary> seededQueue = const [],
  }) async {
    repository = _GatedRosterRepository(_roster)..queue.addAll(seededQueue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectedRunIdProvider.overrideWith((ref) => 'run-1'),
          currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
          rosterRepositoryProvider.overrideWithValue(repository),
          pendingRequestsProvider.overrideWith(
            (ref) async => List.of(repository.queue),
          ),
          todayRunsProvider.overrideWith(
            (ref) async => [managerRunFixture(roleInRun: UserRole.escort)],
          ),
        ],
        child: const MaterialApp(home: RosterScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 그 학생 행의 버튼 — 행은 `StudentRow` 하나가 한 학생이다.
  Finder rowOf(String name) => find.ancestor(
    of: find.text(name),
    matching: find.byType(StudentRow),
  );
  Finder buttonIn(String name, String label) => find.descendant(
    of: rowOf(name),
    matching: find.widgetWithText(BaraedaButton, label),
  );
  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<BaraedaButton>(button).onPressed != null;

  testWidgets('한 학생의 응답을 기다리는 중에 다른 학생을 눌러도 앞 학생의 잠금이 풀리지 않는다 (R46)', (
    tester,
  ) async {
    await pumpRoster(tester);
    final gateA = Completer<SendOutcome<RiderUpdateResult>>();
    final gateB = Completer<SendOutcome<RiderUpdateResult>>();
    repository.gates['r1'] = gateA;
    repository.gates['r2'] = gateB;

    await tester.tap(buttonIn('김바래', '탑승'));
    await tester.pump();
    await tester.tap(buttonIn('이바래', '탑승'));
    await tester.pump();
    expect(enabled(tester, buttonIn('김바래', '탑승')), isFalse);
    expect(enabled(tester, buttonIn('이바래', '탑승')), isFalse);

    gateB.complete(Sent(_result('r2')));
    await tester.pump();
    await tester.pump();

    expect(
      enabled(tester, buttonIn('김바래', '탑승')),
      isFalse,
      reason: '김바래의 응답은 아직 안 왔다 — 뒤에 누른 학생이 끝나도 잠금이 유지돼야 한다',
    );
    expect(enabled(tester, buttonIn('이바래', '탑승')), isTrue);

    gateA.complete(Sent(_result('r1')));
    await tester.pumpAndSettle();
    expect(enabled(tester, buttonIn('김바래', '탑승')), isTrue);
  });

  testWidgets('응답을 기다리는 학생 행에는 진행 표시가 돈다 (R46)', (tester) async {
    await pumpRoster(tester);
    repository.gates['r1'] = Completer<SendOutcome<RiderUpdateResult>>();

    expect(
      find.descendant(
        of: rowOf('김바래'),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    await tester.tap(buttonIn('김바래', '탑승'));
    await tester.pump();

    expect(
      find.descendant(
        of: rowOf('김바래'),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: rowOf('이바래'),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
      reason: '진행 표시는 누른 학생 행에만 있다',
    );
  });

  testWidgets('큐에 쌓인 학생 행은 전송 대기로 바뀌어 같은 처리를 다시 누를 수 없다 (R46)', (tester) async {
    await pumpRoster(tester);
    repository.queuedRiders.add('r1');

    await tester.tap(buttonIn('김바래', '탑승'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: rowOf('김바래'), matching: find.text('전송 대기')),
      findsOneWidget,
    );
    expect(buttonIn('김바래', '탑승'), findsNothing);
    expect(buttonIn('김바래', '미승차'), findsNothing);
    expect(buttonIn('이바래', '탑승'), findsOneWidget, reason: '다른 학생 행은 그대로다');
    expect(repository.calls, ['r1:boarded']);
  });

  // R46-FIXRT S-9 — 서버가 5xx 를 되풀이해 재생에서 뺀 행은 "전송 대기" 가 아니다. 그 학생은 다시 눌러 새로 보낼 수
  // 있어야 하고, 보내지 못한 처리가 있다는 것은 따로 알린다.
  testWidgets('영구 실패 행은 학생 행을 전송 대기로 바꾸지 않고 따로 알린다', (tester) async {
    await pumpRoster(
      tester,
      seededQueue: [
        PendingRequestSummary(
          id: 1,
          endpoint: '/runs/run-1/riders/r1',
          method: 'PATCH',
          payload: '{"status":"boarded"}',
          createdAt: DateTime(2026, 10, 1, 8),
          failed: true,
        ),
      ],
    );

    expect(
      find.descendant(of: rowOf('김바래'), matching: find.text('전송 대기')),
      findsNothing,
    );
    expect(buttonIn('김바래', '탑승'), findsOneWidget, reason: '다시 눌러 새로 보낼 수 있다');
    expect(
      find.text('서버가 계속 받지 못해 보내지 못한 처리 1건 · 대기열에서 확인하세요'),
      findsOneWidget,
    );
    expect(find.textContaining('대기 중 '), findsNothing);
    expect(find.text('대기열 1건'), findsOneWidget);
  });

  testWidgets('대기 안내 배너는 다른 학생을 처리해도 지워지지 않고 대기 건수를 보인다 (R46)', (tester) async {
    await pumpRoster(tester);
    repository.queuedRiders.add('r1');

    await tester.tap(buttonIn('김바래', '탑승'));
    await tester.pumpAndSettle();
    expect(find.text('처리되지 않았습니다 · 대기 중 1건'), findsOneWidget);
    expect(find.text('대기열 1건'), findsOneWidget);

    await tester.tap(buttonIn('이바래', '탑승'));
    await tester.pumpAndSettle();

    expect(
      find.text('처리되지 않았습니다 · 대기 중 1건'),
      findsOneWidget,
      reason: '다음 조작이 배너를 지우면 기사가 큐에 쌓인 처리를 잊는다',
    );
  });
}
