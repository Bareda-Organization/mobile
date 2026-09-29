import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
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
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/roster/data/models/ack_changes_result.dart';
import 'package:manager_app/features/roster/data/models/boarding_update_request.dart';
import 'package:manager_app/features/roster/data/models/no_show_contact_request.dart';
import 'package:manager_app/features/roster/data/models/revert_result.dart';
import 'package:manager_app/features/roster/data/models/rider_update_result.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/domain/roster_repository.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/roster/presentation/roster_screen.dart';

import '../../support/manager_run_fixture.dart';

/// R32 M7 — [미승차]는 [탑승] 바로 옆이라 잘못 눌리기 쉽고 누르면 학부모에게 알림이 나간다.
/// 확인 창을 거치고, 취소하면 요청이 나가지 않는다.
class _RecordingRosterRepository implements RosterRepository {
  _RecordingRosterRepository(this.roster);

  final RosterResponse roster;
  final requestedStatuses = <RiderStatus>[];

  @override
  Future<RosterResponse> fetchRoster(String runId) async => roster;

  @override
  Future<SendOutcome<RiderUpdateResult>> updateRiderStatus({
    required String runId,
    required String riderId,
    required BoardingUpdateRequest request,
  }) async {
    requestedStatuses.add(request.status);
    // 요청이 나갔는지만 본다 — 성공 응답을 만들지 않고 실패로 끝낸다.
    // Failure 는 Exception/Error 를 상속하지 않는다(다른 시험의 같은 패턴).
    // ignore: only_throw_errors
    throw const NetworkFailure();
  }

  @override
  Future<AckChangesResult> ackChanges({required String runId}) =>
      throw UnimplementedError();

  @override
  Future<RevertResult> revertRiderStatus({
    required String runId,
    required String riderId,
    String? reason,
  }) => throw UnimplementedError();

  @override
  Future<void> recordNoShowContact({
    required String runId,
    required String riderId,
    required NoShowContactRequest request,
  }) => throw UnimplementedError();
}

class _NeverResolvingTokenStorage extends TokenStorage {
  _NeverResolvingTokenStorage()
    : super(
        accessTokenKey: 'test_access_token',
        refreshTokenKey: 'test_refresh_token',
      );

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;
}

const _roster = RosterResponse(
  runId: 'run-1',
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  counts: RosterCounts(boarded: 0, waiting: 1, noShow: 0, absentN: 0),
  stops: [
    RosterStop(
      stopId: 'st1',
      seq: 1,
      name: 'A정류장',
      students: [
        RosterStudent(
          riderId: 'r1',
          studentId: 's1',
          name: '김바래',
          photoUrl: null,
          guardianPhone: null,
          canGoAlone: false,
          status: RiderStatus.waiting,
        ),
      ],
    ),
  ],
);

void main() {
  Future<_RecordingRosterRepository> pumpRoster(WidgetTester tester) async {
    final repository = _RecordingRosterRepository(_roster);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
          selectedRunIdProvider.overrideWith((ref) => 'run-1'),
          currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
          todayRunsProvider.overrideWith((ref) async => [managerRunFixture()]),
          rosterRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: RosterScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('미승차 — 취소하면 요청이 나가지 않고, 확인해야 나간다', (tester) async {
    final repository = await pumpRoster(tester);

    await tester.tap(find.widgetWithText(BaraedaButton, '미승차'));
    await tester.pumpAndSettle();
    expect(find.text('김바래 학생을 미승차로 처리할까요?'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(repository.requestedStatuses, isEmpty);

    await tester.tap(find.widgetWithText(BaraedaButton, '미승차'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('미승차 처리'));
    await tester.pumpAndSettle();
    expect(repository.requestedStatuses, [RiderStatus.noShow]);
  });

  testWidgets('탑승은 확인 없이 바로 나간다(정상 흐름은 한 번에)', (tester) async {
    final repository = await pumpRoster(tester);

    await tester.tap(find.widgetWithText(BaraedaButton, '탑승'));
    await tester.pumpAndSettle();

    expect(repository.requestedStatuses, [RiderStatus.boarded]);
  });
}
