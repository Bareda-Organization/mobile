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
import 'package:manager_app/features/roster/presentation/roster_screen.dart';

import '../../support/manager_run_fixture.dart';

/// Z-05(BR-254) — 미승차를 되돌려 `waiting` 으로 돌아간 탑승자에게 연락 기록을 보내면 서버가
/// `404 NO_SHOW_CASE_NOT_FOUND` 를 준다. 화면이 죽지 않고 이유를 알리며, 낡은 명단을 다시 불러온다.
class _ContactFailingRepository implements RosterRepository {
  new(this.roster);

  final RosterResponse roster;
  int fetchCount = 0;

  @override
  Future<RosterResponse> fetchRoster(String runId) async {
    fetchCount++;
    return roster;
  }

  @override
  Future<void> recordNoShowContact({
    required String runId,
    required String riderId,
    required NoShowContactRequest request,
  }) async {
    // Failure 는 Exception/Error 를 상속하지 않는다(다른 시험의 같은 패턴).
    // ignore: only_throw_errors
    throw const ApiFailure(
      statusCode: 404,
      code: 'NO_SHOW_CASE_NOT_FOUND',
      message: '서버 원문',
    );
  }

  @override
  Future<SendOutcome<RiderUpdateResult>> updateRiderStatus({
    required String runId,
    required String riderId,
    required BoardingUpdateRequest request,
  }) => throw UnimplementedError();

  @override
  Future<AckChangesResult> ackChanges({required String runId}) =>
      throw UnimplementedError();

  @override
  Future<RevertResult> revertRiderStatus({
    required String runId,
    required String riderId,
    String? reason,
  }) => throw UnimplementedError();
}

class _NeverResolvingTokenStorage extends TokenStorage {
  new()
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
  counts: RosterCounts(boarded: 0, waiting: 0, noShow: 1, absentN: 0),
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
          status: RiderStatus.noShow,
        ),
      ],
    ),
  ],
);

void main() {
  testWidgets('404 NO_SHOW_CASE_NOT_FOUND 면 이유를 알리고 명단을 다시 불러온다', (
    tester,
  ) async {
    final repository = _ContactFailingRepository(_roster);
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
    expect(repository.fetchCount, 1);

    await tester.tap(find.widgetWithText(BaraedaButton, '연락 기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BaraedaButton, '기록 저장'));
    await tester.pumpAndSettle();

    expect(
      find.text('미승차가 이미 되돌려져 연락을 기록할 수 없습니다 — 명단을 새로 불러왔습니다'),
      findsOneWidget,
    );
    expect(find.text('서버 원문'), findsNothing);
    expect(repository.fetchCount, 2);
  });
}
