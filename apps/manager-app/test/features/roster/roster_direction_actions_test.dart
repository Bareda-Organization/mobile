import 'package:baraeda_core/testing.dart';
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

RosterStudent _student(
  String id,
  String name,
  RiderStatus status, {
  bool canGoAlone = true,
}) => RosterStudent(
  riderId: id,
  studentId: 's$id',
  name: name,
  photoUrl: null,
  guardianPhone: null,
  canGoAlone: canGoAlone,
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
        _student('r2', '대기아이', RiderStatus.waiting, canGoAlone: false),
      ],
    ),
  ],
);

void main() {
  Future<void> pump(WidgetTester tester, RunDirection direction) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(NeverResolvingTokenStorage()),
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

  // 하원 waiting→no_show 는 종료 보류 회차를 끝내는 유일한 정리 경로다(BR-031 · C-15) —
  // 서버도 방향 무관으로 둔다. 서버가 막는 것은 등원 boarded→alighted · 하원
  // waiting→boarded 둘뿐이라 앱이 숨기는 것도 그 둘이다.
  testWidgets('하원 — 탑승 학생은 [하차], 대기 학생은 [탑승] 없이 [미승차] 만 남는다', (tester) async {
    await pump(tester, RunDirection.fromAcademy);

    expect(button('하차'), findsOneWidget);
    expect(button('탑승'), findsNothing);
    expect(button('미승차'), findsOneWidget);
    expect(button('되돌리기'), findsOneWidget);
  });

  // A16 — 혼자 귀가 여부는 하원에서만 뜻이 있다(C-07). 등원 회차에는 경고를 내지 않는다.
  testWidgets('혼자 귀가 불가 경고는 하원에만 뜨고 등원에는 뜨지 않는다', (tester) async {
    await pump(tester, RunDirection.toAcademy);
    expect(find.text('혼자 귀가 불가 · 보호자 확인'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await pump(tester, RunDirection.fromAcademy);
    expect(find.text('혼자 귀가 불가 · 보호자 확인'), findsOneWidget);
  });
}
