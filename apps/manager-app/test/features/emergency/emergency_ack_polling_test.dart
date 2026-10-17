import 'package:baraeda_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/ui/countdown_tick.dart';
import 'package:manager_app/features/emergency/data/models/emergency_item.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_request.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_result.dart';
import 'package:manager_app/features/emergency/data/models/emergency_type.dart';
import 'package:manager_app/features/emergency/domain/emergency_repository.dart';
import 'package:manager_app/features/emergency/presentation/emergency_screen.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';

import '../../support/manager_run_fixture.dart';

/// 발신은 항상 성공하고, 이력 조회는 [acked] 가 켜진 뒤에야 "학원이 확인함" 으로 답하는 가짜.
class _Repo implements EmergencyRepository {
  new(this.raisedAt);

  final DateTime raisedAt;
  bool acked = false;
  int fetches = 0;

  @override
  Future<SendOutcome<EmergencyRaiseResult>> raise({
    required String runId,
    required EmergencyRaiseRequest request,
  }) async => Sent(
    EmergencyRaiseResult(
      emergencyId: 'e1',
      raisedAt: raisedAt,
      cancelableUntil: raisedAt.add(const Duration(minutes: 1)),
      notified: 2,
    ),
  );

  @override
  Future<void> cancel({
    required String runId,
    required String emergencyId,
  }) async {}

  @override
  Future<EmergencyListResponse> fetchList({required String runId}) async {
    fetches++;
    return EmergencyListResponse(
      items: [
        EmergencyItem(
          emergencyId: 'e1',
          type: EmergencyType.accident,
          raisedAt: raisedAt,
          cancelableUntil: raisedAt.add(const Duration(minutes: 1)),
          acked: acked,
          ackedAt: acked ? raisedAt.add(const Duration(minutes: 2)) : null,
          ackedByName: acked ? '최은영' : null,
        ),
      ],
    );
  }
}

class _NoPosition implements PositionSource {
  const new();

  @override
  Future<PositionSample?> sampleOnce({
    Duration timeout = const Duration(seconds: 5),
  }) async => null;

  @override
  PositionSample? sample() => null;

  @override
  PositionAvailability get availability => PositionAvailability.available;

  @override
  Future<void> recheck() async {}

  @override
  void start() {}

  @override
  void stop() {}
}

/// R53 t4 A3 — 실시간 채널(운행 화면이 연다)이 없는 곳(홈 · 알림 · 내 정보 · 운행 준비)에서 보낸 비상은
/// "학원이 확인했어요" 로 저절로 바뀌지 않았다. 확인 대기 동안 짧은 주기로 이력을 다시 받는다.
void main() {
  final raisedAt = DateTime(2026, 10, 11, 9);

  Future<_Repo> pumpAndRaise(WidgetTester tester) async {
    final repo = _Repo(raisedAt);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          countdownTickProvider.overrideWith(
            (ref) => const Stream<int>.empty(),
          ),
          todayRunsProvider.overrideWith(
            (ref) async => [managerRunFixture(status: RunStatus.moving)],
          ),
          pendingRequestsProvider.overrideWith((ref) async => const []),
          selectedRunIdProvider.overrideWith((ref) => 'run-1'),
          emergencyRepositoryProvider.overrideWithValue(repo),
          clockProvider.overrideWithValue(FixedClock(raisedAt)),
          positionSourceProvider.overrideWithValue(const _NoPosition()),
        ],
        child: const MaterialApp(home: EmergencyScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('비상 알림 보내기'));
    await tester.pumpAndSettle();
    expect(find.text('비상 알림을 보냈어요'), findsOneWidget);
    return repo;
  }

  testWidgets('확인 대기 중에 주기가 지나면 이력을 다시 받아 "학원이 확인했어요" 로 바뀐다', (tester) async {
    final repo = await pumpAndRaise(tester);

    repo.acked = true;
    await tester.pump(emergencyAckPollInterval);
    await tester.pumpAndSettle();

    expect(find.text('학원이 확인했어요'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('확인이 끝나면 더는 다시 받지 않는다', (tester) async {
    final repo = await pumpAndRaise(tester);
    repo.acked = true;
    await tester.pump(emergencyAckPollInterval);
    await tester.pumpAndSettle();
    final fetched = repo.fetches;

    await tester.pump(emergencyAckPollInterval * 3);
    await tester.pumpAndSettle();

    expect(repo.fetches, fetched);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('신고를 보내기 전에는 주기가 지나도 이력을 다시 받지 않는다', (tester) async {
    final repo = _Repo(raisedAt);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          countdownTickProvider.overrideWith(
            (ref) => const Stream<int>.empty(),
          ),
          todayRunsProvider.overrideWith(
            (ref) async => [managerRunFixture(status: RunStatus.moving)],
          ),
          pendingRequestsProvider.overrideWith((ref) async => const []),
          selectedRunIdProvider.overrideWith((ref) => 'run-1'),
          emergencyRepositoryProvider.overrideWithValue(repo),
          clockProvider.overrideWithValue(FixedClock(raisedAt)),
          positionSourceProvider.overrideWithValue(const _NoPosition()),
        ],
        child: const MaterialApp(home: EmergencyScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final fetched = repo.fetches;

    await tester.pump(emergencyAckPollInterval * 3);
    await tester.pumpAndSettle();

    expect(repo.fetches, fetched);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
