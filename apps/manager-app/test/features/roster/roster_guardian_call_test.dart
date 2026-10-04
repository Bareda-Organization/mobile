import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/launcher/device_launchers.dart';
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
import 'package:manager_app/features/roster/domain/guardian_phone_repository.dart';
import 'package:manager_app/features/roster/domain/roster_repository.dart';
import 'package:manager_app/features/roster/presentation/roster_screen.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_widgets.dart';

import '../../support/manager_run_fixture.dart';

/// Ruling 482 — 명단의 보호자 번호는 마스킹이라 걸 수 없다. [전화] 를 누르면 그 탑승자 1명의 원번호를 서버에서
/// 받아 `tel:` 로 연다. 원번호는 화면에 싣지 않고(바로 전화만), 조회가 실패하면 전화를 걸지 않고 이유를 알린다.
class _FixedRosterRepository implements RosterRepository {
  const new(this.roster);

  final RosterResponse roster;

  @override
  Future<RosterResponse> fetchRoster(String runId) async => roster;

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

  @override
  Future<AckChangesResult> ackChanges({required String runId}) =>
      throw UnimplementedError();
}

class _FakeGuardianPhones implements GuardianPhoneRepository {
  new({this.phone, this.failure});

  final String? phone;
  final Failure? failure;
  final List<(String, String)> requested = [];

  @override
  Future<String?> fetchGuardianPhone({
    required String runId,
    required String riderId,
  }) async {
    requested.add((runId, riderId));
    // Failure 는 Exception/Error 를 상속하지 않는다(다른 시험의 같은 패턴).
    // ignore: only_throw_errors
    if (failure != null) throw failure!;
    return phone;
  }
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

const _rawPhone = '010-2345-8814';

RosterResponse _rosterOf({required RiderStatus status, String? maskedPhone}) {
  return RosterResponse(
    runId: 'run-1',
    busNo: '3호차',
    direction: RunDirection.toAcademy,
    counts: const RosterCounts(boarded: 0, waiting: 1, noShow: 0, absentN: 0),
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
            guardianPhone: maskedPhone,
            canGoAlone: false,
            status: status,
          ),
        ],
      ),
    ],
  );
}

Future<List<Uri>> _pump(
  WidgetTester tester, {
  required RosterResponse roster,
  required _FakeGuardianPhones phones,
  bool openerSucceeds = true,
}) async {
  final opened = <Uri>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
        selectedRunIdProvider.overrideWith((ref) => 'run-1'),
        currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
        todayRunsProvider.overrideWith((ref) async => [managerRunFixture()]),
        rosterRepositoryProvider.overrideWithValue(
          _FixedRosterRepository(roster),
        ),
        guardianPhoneRepositoryProvider.overrideWithValue(phones),
        uriOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return openerSucceeds;
        }),
      ],
      child: const MaterialApp(home: RosterScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  testWidgets('[전화] 를 누르면 원번호를 받아 tel: 로 열고 원번호는 화면에 싣지 않는다', (tester) async {
    final phones = _FakeGuardianPhones(phone: _rawPhone);
    final opened = await _pump(
      tester,
      roster: _rosterOf(
        status: RiderStatus.waiting,
        maskedPhone: '010-2XXX-8814',
      ),
      phones: phones,
    );
    expect(find.textContaining('010-2XXX-8814'), findsOneWidget);

    await tester.tap(find.byType(RosterCallButton));
    await tester.pumpAndSettle();

    expect(phones.requested, [('run-1', 'r1')]);
    expect(opened, [Uri(scheme: 'tel', path: _rawPhone)]);
    expect(find.textContaining(_rawPhone), findsNothing);
  });

  testWidgets('미승차 행에도 [전화] 가 있다', (tester) async {
    await _pump(
      tester,
      roster: _rosterOf(
        status: RiderStatus.noShow,
        maskedPhone: '010-2XXX-8814',
      ),
      phones: _FakeGuardianPhones(phone: _rawPhone),
    );

    expect(find.byType(RosterCallButton), findsOneWidget);
  });

  testWidgets('조회가 거부되면 전화를 걸지 않고 이유를 알린다', (tester) async {
    final phones = _FakeGuardianPhones(
      failure: const ApiFailure(
        statusCode: 403,
        code: 'FORBIDDEN',
        message: '서버 원문',
      ),
    );
    final opened = await _pump(
      tester,
      roster: _rosterOf(
        status: RiderStatus.waiting,
        maskedPhone: '010-2XXX-8814',
      ),
      phones: phones,
    );

    await tester.tap(find.byType(RosterCallButton));
    await tester.pumpAndSettle();

    expect(opened, isEmpty);
    expect(find.textContaining('보호자 번호를 가져오지 못했어요'), findsOneWidget);
    expect(find.textContaining('이 회차를 이용할 권한이 없습니다'), findsOneWidget);
  });

  testWidgets('통신이 끊기면 전화를 걸지 않고 네트워크 안내를 한다', (tester) async {
    final phones = _FakeGuardianPhones(failure: const NetworkFailure());
    final opened = await _pump(
      tester,
      roster: _rosterOf(
        status: RiderStatus.waiting,
        maskedPhone: '010-2XXX-8814',
      ),
      phones: phones,
    );

    await tester.tap(find.byType(RosterCallButton));
    await tester.pumpAndSettle();

    expect(opened, isEmpty);
    expect(find.textContaining('네트워크 상태를 확인해 주세요'), findsOneWidget);
  });

  testWidgets('서버가 번호 없음(null)으로 답하면 전화를 걸지 않고 안내한다', (tester) async {
    final opened = await _pump(
      tester,
      roster: _rosterOf(
        status: RiderStatus.waiting,
        maskedPhone: '010-2XXX-8814',
      ),
      phones: _FakeGuardianPhones(),
    );

    await tester.tap(find.byType(RosterCallButton));
    await tester.pumpAndSettle();

    expect(opened, isEmpty);
    expect(find.text('등록된 보호자 연락처가 없어요'), findsOneWidget);
  });

  testWidgets('전화 앱을 열지 못하면 그 사실을 알린다', (tester) async {
    await _pump(
      tester,
      roster: _rosterOf(
        status: RiderStatus.waiting,
        maskedPhone: '010-2XXX-8814',
      ),
      phones: _FakeGuardianPhones(phone: _rawPhone),
      openerSucceeds: false,
    );

    await tester.tap(find.byType(RosterCallButton));
    await tester.pumpAndSettle();

    expect(find.text('전화 앱을 열지 못했어요'), findsOneWidget);
  });

  testWidgets('연결된 보호자가 없는 학생 행에는 [전화] 가 없다', (tester) async {
    await _pump(
      tester,
      roster: _rosterOf(status: RiderStatus.waiting),
      phones: _FakeGuardianPhones(phone: _rawPhone),
    );

    expect(find.byType(RosterCallButton), findsNothing);
  });
}
