import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/run_termination_provider.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/roster/presentation/roster_screen.dart';
import 'package:manager_app/features/run_end/presentation/run_end_screen.dart';

import '../../support/manager_run_fixture.dart';

/// R32 M3 — 예외 보고(§4.13 · M-14)는 기사·동승자 공통인데 지금까지 기사 운행 화면에서만
/// 닿았다. 동승자는 명단 화면에서 보고할 수 있어야 하고, 도착 결과가 없는 그 경로에서는
/// 대상 학생 목록을 명단에서 만든다(보호자 부재 = 혼자 귀가할 수 없는 탑승 중 학생).
class _NeverResolvingTokenStorage extends TokenStorage {
  _NeverResolvingTokenStorage()
    : super(
        accessTokenKey: 'test_access_token',
        refreshTokenKey: 'test_refresh_token',
      );

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;
}

RosterStudent _student(
  String id,
  String name, {
  required bool canGoAlone,
  required RiderStatus status,
}) => RosterStudent(
  riderId: id,
  studentId: 's$id',
  name: name,
  photoUrl: null,
  guardianPhone: null,
  canGoAlone: canGoAlone,
  status: status,
);

RosterResponse _roster(List<RosterStudent> students) => RosterResponse(
  runId: 'run-1',
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  counts: const RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
  stops: [
    RosterStop(stopId: 'st1', seq: 1, name: 'A정류장', students: students),
  ],
);

void main() {
  testWidgets('명단 화면 — 동승자 머리말의 예외 보고 버튼이 보고 화면으로 간다', (tester) async {
    final router = GoRouter(
      initialLocation: AppRoutes.roster,
      routes: [
        GoRoute(
          path: AppRoutes.roster,
          builder: (_, _) => const RosterScreen(),
        ),
        GoRoute(
          path: AppRoutes.runEnd,
          builder: (_, _) => const Text('RUN_END_MARKER'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
          selectedRunIdProvider.overrideWith((ref) => 'run-1'),
          todayRunsProvider.overrideWith((ref) async => [managerRunFixture()]),
          rosterProvider.overrideWith((ref) async => _roster(const [])),
          currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('예외 보고'));
    await tester.pumpAndSettle();

    expect(find.text('RUN_END_MARKER'), findsOneWidget);
  });

  testWidgets('도착 결과 없이 들어오면 종료 안내 대신 예외 보고 화면이고, 대상은 명단에서 만든다', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectedRunIdProvider.overrideWith((ref) => 'run-1'),
          lastArriveResultProvider.overrideWith((ref) => null),
          rosterProvider.overrideWith(
            (ref) async => _roster([
              _student(
                'r1',
                '김바래',
                canGoAlone: false,
                status: RiderStatus.boarded,
              ),
              _student(
                'r2',
                '이혼자',
                canGoAlone: true,
                status: RiderStatus.boarded,
              ),
              _student(
                'r3',
                '박대기',
                canGoAlone: false,
                status: RiderStatus.waiting,
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: RunEndScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('종료 정보가 없습니다'), findsNothing);
    expect(find.text('예외 보고'), findsWidgets);
    final select = tester.widget<BaraedaSelect>(find.byType(BaraedaSelect));
    expect(select.options.map((o) => o.label), ['김바래']);
  });
}
