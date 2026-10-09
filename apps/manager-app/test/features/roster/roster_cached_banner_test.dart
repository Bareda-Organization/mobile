import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/roster/presentation/roster_screen.dart';

import '../../support/manager_run_fixture.dart';

/// M-M3(UF-E-07) — 서버에 닿지 못해 기기에 저장해 둔 명단을 보고 있으면 화면이 그렇다고 밝히고, 연결이 돌아왔는지
/// 주기마다 다시 받아 본다. 서버에서 방금 받은 명단에는 이 안내가 없다.
class _NeverResolvingTokenStorage extends TokenStorage {
  new() : super(accessTokenKey: 'a', refreshTokenKey: 'r');

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;
}

RosterResponse _roster({DateTime? cachedAt}) => RosterResponse(
  runId: 'run-1',
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  counts: const RosterCounts(boarded: 0, waiting: 1, noShow: 0, absentN: 0),
  stops: const [
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
          canGoAlone: true,
          status: RiderStatus.waiting,
        ),
      ],
    ),
  ],
  cachedAt: cachedAt,
);

void main() {
  Future<({int Function() loads})> pump(
    WidgetTester tester, {
    DateTime? cachedAt,
  }) async {
    var loads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
          selectedRunIdProvider.overrideWith((ref) => 'run-1'),
          currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
          todayRunsProvider.overrideWith((ref) async => [managerRunFixture()]),
          rosterProvider.overrideWith((ref) async {
            loads++;
            return _roster(cachedAt: cachedAt);
          }),
        ],
        child: const MaterialApp(home: RosterScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return (loads: () => loads);
  }

  testWidgets('저장해 둔 명단을 보고 있으면 받은 시각과 함께 밝힌다', (tester) async {
    await pump(tester, cachedAt: DateTime(2026, 10, 10, 7, 41));

    expect(find.text('저장된 명단을 보고 있어요'), findsOneWidget);
    expect(find.textContaining('07:41'), findsOneWidget);
    expect(find.text('김바래'), findsOneWidget);
  });

  testWidgets('서버에서 방금 받은 명단에는 저장본 안내가 없다', (tester) async {
    await pump(tester);

    expect(find.text('저장된 명단을 보고 있어요'), findsNothing);
  });

  testWidgets('저장본을 보는 동안은 주기마다 서버에서 다시 받아 본다', (tester) async {
    final harness = await pump(
      tester,
      cachedAt: DateTime(2026, 10, 10, 7, 41),
    );
    expect(harness.loads(), 1);

    await tester.pump(const Duration(seconds: 16));
    await tester.pump();

    expect(harness.loads(), greaterThan(1));
  });

  testWidgets('서버에서 받은 명단은 주기 재조회를 하지 않는다', (tester) async {
    final harness = await pump(tester);

    await tester.pump(const Duration(seconds: 40));
    await tester.pump();

    expect(harness.loads(), 1);
  });
}
