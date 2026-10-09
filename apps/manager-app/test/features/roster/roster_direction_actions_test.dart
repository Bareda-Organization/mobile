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
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/roster/presentation/roster_screen.dart';

import '../../support/manager_run_fixture.dart';

/// M-M4(C-07 · BRD-01·02) — 등하원 비대칭. 승차 처리([탑승]·[미승차])는 등원 승하차지의 일이고
/// 하차 처리([하차])는 하원 승하차지의 일이다. 서버 전이 표(`waiting→boarded` · `waiting→no_show` ·
/// `boarded→alighted`)는 방향을 가리지 않으므로 사양 밖 단추는 앱이 그리지 않는다.
/// 오조작을 바로잡는 [되돌리기]는 방향과 무관하다.
class _NeverResolvingTokenStorage extends TokenStorage {
  new() : super(accessTokenKey: 'a', refreshTokenKey: 'r');

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;
}

RosterStudent _student(String id, String name, RiderStatus status) =>
    RosterStudent(
      riderId: id,
      studentId: 's$id',
      name: name,
      photoUrl: null,
      guardianPhone: null,
      canGoAlone: true,
      status: status,
    );

RosterResponse _roster(RunDirection direction) => RosterResponse(
  runId: 'run-1',
  busNo: '3호차',
  direction: direction,
  counts: const RosterCounts(boarded: 1, waiting: 1, noShow: 0, absentN: 0),
  stops: [
    RosterStop(
      stopId: 'st1',
      seq: 1,
      name: 'A정류장',
      students: [
        _student('r1', '탄아이', RiderStatus.boarded),
        _student('r2', '대기아이', RiderStatus.waiting),
      ],
    ),
  ],
);

void main() {
  Future<void> pump(WidgetTester tester, RunDirection direction) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
          selectedRunIdProvider.overrideWith((ref) => 'run-1'),
          currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
          todayRunsProvider.overrideWith(
            (ref) async => [managerRunFixture(direction: direction)],
          ),
          rosterProvider.overrideWith((ref) async => _roster(direction)),
        ],
        child: const MaterialApp(home: RosterScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder button(String label) => find.widgetWithText(BaraedaButton, label);

  testWidgets('등원 — 대기 학생은 [탑승]·[미승차], 탑승 학생에 [하차] 는 없다', (tester) async {
    await pump(tester, RunDirection.toAcademy);

    expect(button('탑승'), findsOneWidget);
    expect(button('미승차'), findsOneWidget);
    expect(button('하차'), findsNothing);
    // 오조작 정정은 방향과 무관하다.
    expect(button('되돌리기'), findsOneWidget);
  });

  testWidgets('하원 — 탑승 학생은 [하차], 대기 학생에 [탑승]·[미승차] 는 없다', (tester) async {
    await pump(tester, RunDirection.fromAcademy);

    expect(button('하차'), findsOneWidget);
    expect(button('탑승'), findsNothing);
    expect(button('미승차'), findsNothing);
    expect(button('되돌리기'), findsOneWidget);
  });
}
