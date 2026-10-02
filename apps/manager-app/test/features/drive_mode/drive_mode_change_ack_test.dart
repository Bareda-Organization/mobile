import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_screen.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/roster/data/models/ack_changes_result.dart';
import 'package:manager_app/features/roster/data/models/boarding_update_request.dart';
import 'package:manager_app/features/roster/data/models/no_show_contact_request.dart';
import 'package:manager_app/features/roster/data/models/revert_result.dart';
import 'package:manager_app/features/roster/data/models/rider_update_result.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/domain/roster_repository.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

import '../../support/manager_run_fixture.dart';

/// R32 M4 — 노선 변경 확인 띠(M-04)는 기사·동승자 공통인데 명단 화면에만 있어, 명단에 가지
/// 않는 기사는 확인할 길이 없었다. 운행 화면에도 같은 띠가 떠야 한다.
class _NeverResolvingTokenStorage extends TokenStorage {
  new()
    : super(
        accessTokenKey: 'test_access_token',
        refreshTokenKey: 'test_refresh_token',
      );

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;
}

class _NoSample implements PositionSource {
  @override
  PositionAvailability get availability => PositionAvailability.available;

  @override
  PositionSample? sample() => null;

  @override
  Future<void> recheck() async {}

  @override
  void start() {}

  @override
  void stop() {}

  @override
  Future<PositionSample?> sampleOnce({
    Duration timeout = const Duration(seconds: 5),
  }) async => null;
}

/// 확인 요청(§4.11)만 기록하는 대역 — 나머지는 이 시험의 대상이 아니다.
class _AckRecordingRosterRepository implements RosterRepository {
  new({this.failure});

  final Failure? failure;
  final ackedRunIds = <String>[];

  @override
  Future<AckChangesResult> ackChanges({required String runId}) async {
    ackedRunIds.add(runId);
    // Failure 는 Exception/Error 를 상속하지 않는다(다른 시험의 같은 패턴).
    // ignore: only_throw_errors
    if (failure != null) throw failure!;
    return AckChangesResult(ackedAt: DateTime(2026, 9, 30, 8));
  }

  @override
  Future<RosterResponse> fetchRoster(String runId) =>
      throw UnimplementedError();

  @override
  Future<SendOutcome<RiderUpdateResult>> updateRiderStatus({
    required String runId,
    required String riderId,
    required BoardingUpdateRequest request,
  }) => throw UnimplementedError();

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

const _emptyRoster = RosterResponse(
  runId: 'run-1',
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  counts: RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
  stops: [],
);

void main() {
  Future<void> pumpDrive(
    WidgetTester tester, {
    required bool ackRequired,
    required _AckRecordingRosterRepository repository,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
          positionSourceProvider.overrideWithValue(_NoSample()),
          routeProvider.overrideWith(
            (ref) async => const RouteResponse(stops: []),
          ),
          selectedRunIdProvider.overrideWith((ref) => 'run-1'),
          currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
          todayRunsProvider.overrideWith(
            (ref) async => [managerRunFixture(ackRequired: ackRequired)],
          ),
          driveModeRosterProvider.overrideWith((ref) async => _emptyRoster),
          rosterRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: DriveModeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('확인이 필요한 변경이 없으면 띠가 없다', (tester) async {
    await pumpDrive(
      tester,
      ackRequired: false,
      repository: _AckRecordingRosterRepository(),
    );

    expect(find.text('변경 목록 확인'), findsNothing);
  });

  testWidgets('확인이 필요한 변경이 있으면 운행 화면에도 띠가 뜨고, 누르면 확인 요청을 보낸다', (
    tester,
  ) async {
    final repository = _AckRecordingRosterRepository();
    await pumpDrive(tester, ackRequired: true, repository: repository);

    expect(find.textContaining('변경됐습니다'), findsOneWidget);
    await tester.tap(find.text('변경 목록 확인'));
    await tester.pump();
    await tester.pump();

    expect(repository.ackedRunIds, ['run-1']);
  });

  testWidgets('확인 요청이 실패하면 띠를 닫지 않고 이유를 보여준다', (tester) async {
    final repository = _AckRecordingRosterRepository(
      failure: const NetworkFailure(),
    );
    await pumpDrive(tester, ackRequired: true, repository: repository);

    await tester.tap(find.text('변경 목록 확인'));
    await tester.pump();
    await tester.pump();

    expect(find.text('변경 목록 확인'), findsOneWidget);
    expect(find.textContaining('네트워크'), findsOneWidget);
  });
}
