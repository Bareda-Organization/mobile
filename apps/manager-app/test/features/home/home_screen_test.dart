import 'dart:async';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/home/presentation/home_screen.dart';

import '../../support/fake_notification_repository.dart';

/// `ManagerHomeScreen` 3갈래(로딩·성공·실패)와 역할별 이동 대상(§4.1, M-02·
/// M-07)을 직접 무는 시험 — 지금까지 이 화면을 검사하는 파일이 없었다.
///
/// 실제 `driveMode`·`roster` 화면 대신 표식 문구만 그리는 가짜 라우트를
/// 붙인다 — 이 시험의 관심사는 "탭했을 때 *어느 경로로* 넘어가는가" 하나뿐이고,
/// 실제 화면을 붙이면 그 화면이 요구하는 다른 provider 까지 채워야 해서
/// 관심사가 흐려진다(`router_redirect_test.dart` 는 반대로 계정 상태 게이트가
/// 관심사라 실제 화면이 필요했던 경우다).
void main() {
  ManagerRun confirmedRun({DateTime? departTime}) {
    final now = departTime ?? DateTime(2026, 9, 12, 8);
    return ManagerRun(
      runId: 'run-1',
      busNo: '3호차',
      direction: RunDirection.toAcademy,
      departTime: now,
      origin: '기점',
      destination: '학원',
      estDurationMin: 30,
      runStatus: RunStatus.confirmed,
      confirmed: true,
      startWindowFrom: now.subtract(const Duration(minutes: 10)),
      startWindowTo: now.add(const Duration(minutes: 10)),
      addedCount: 0,
      removedCount: 0,
      ackRequired: false,
    );
  }

  GoRouter buildRouter() => GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const ManagerHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.driveMode,
        builder: (context, state) => const Text('DRIVE_MODE_SCREEN_MARKER'),
      ),
      GoRoute(
        path: AppRoutes.roster,
        builder: (context, state) => const Text('ROSTER_SCREEN_MARKER'),
      ),
    ],
  );

  Widget wrap(List<Override> overrides) {
    return ProviderScope(
      overrides: [
        // 머리말 알림 배지가 실제 서버를 부르지 않게 한다(R46).
        notificationRepositoryProvider.overrideWithValue(
          FakeNotificationRepository(const []),
        ),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: buildRouter()),
    );
  }

  // ⚠ 2026-09-21 실측(학부모 앱에서 먼저 드러났다) — 서버 시각은 **UTC 순간**인데
  // 화면이 그대로 벽시계로 읽어 KST 에서 **9시간 이른 시각**이 나왔다.
  // 기대값을 `toLocal()` 로 계산하는 이유는 시험기의 표준시를 바꿀 수단이
  // 부재하기 때문이다 — UTC 기계에서는 무해하게 통과하고 KST 에서 문다.
  testWidgets('출발 시각을 기기 표준시로 보여준다', (tester) async {
    final departUtc = DateTime.utc(2026, 9, 21, 10, 40);
    await tester.pumpWidget(
      wrap([
        todayRunsProvider.overrideWith(
          (ref) async => [confirmedRun(departTime: departUtc)],
        ),
        currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
      ]),
    );
    await tester.pumpAndSettle();

    final local = departUtc.toLocal();
    final expected =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    // 시각만 크게 있으면 출발인지 도착인지 모른다 — 앞에 "출발" 을 붙인다(R46, B2 #25).
    expect(find.text('출발 $expected'), findsOneWidget);
  });

  testWidgets('로딩 중에는 진행 표시기를 보여준다', (tester) async {
    final neverCompletes = Completer<List<ManagerRun>>().future;
    await tester.pumpWidget(
      wrap([todayRunsProvider.overrideWith((ref) => neverCompletes)]),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('불러오기 실패 시 실패 사유를 보여준다', (tester) async {
    await tester.pumpWidget(
      wrap([
        todayRunsProvider.overrideWith(
          (ref) async => throw Exception('네트워크 오류'),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('오늘 운행을 불러오지 못했습니다'), findsOneWidget);
  });

  testWidgets('기사 역할이면 확정된 회차를 눌렀을 때 운행 모드로 이동한다', (tester) async {
    await tester.pumpWidget(
      wrap([
        todayRunsProvider.overrideWith((ref) async => [confirmedRun()]),
        currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(RunSummaryCard));
    await tester.pumpAndSettle();

    expect(find.text('DRIVE_MODE_SCREEN_MARKER'), findsOneWidget);
    expect(find.text('ROSTER_SCREEN_MARKER'), findsNothing);
  });

  testWidgets('동승자 역할이면 확정된 회차를 눌렀을 때 승하차 명단으로 이동한다', (tester) async {
    await tester.pumpWidget(
      wrap([
        todayRunsProvider.overrideWith((ref) async => [confirmedRun()]),
        currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(RunSummaryCard));
    await tester.pumpAndSettle();

    expect(find.text('ROSTER_SCREEN_MARKER'), findsOneWidget);
    expect(find.text('DRIVE_MODE_SCREEN_MARKER'), findsNothing);
  });

  testWidgets(
    '역할이 미상(null)이면 운행 시작 쪽이 아니라 닫힌 쪽(승하차 명단)으로 간다 '
    '— 모르면 막는 쪽이 기본값이어야 한다',
    (tester) async {
      await tester.pumpWidget(
        // currentUserRoleProvider 를 override 하지 않는다 — 기본값 null 로
        // roleCapabilitiesProvider 도 null 이 된다.
        wrap([
          todayRunsProvider.overrideWith((ref) async => [confirmedRun()]),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(RunSummaryCard));
      await tester.pumpAndSettle();

      expect(find.text('ROSTER_SCREEN_MARKER'), findsOneWidget);
      expect(find.text('DRIVE_MODE_SCREEN_MARKER'), findsNothing);
    },
  );

  // R32 M9 — 확정 전 카드는 눌러도 반응이 없는데 이유를 알려 주지 않았다.
  testWidgets('확정 전 회차는 언제 열리는지 알려 준다', (tester) async {
    final run = ManagerRun(
      runId: 'run-2',
      busNo: '5호차',
      direction: RunDirection.toAcademy,
      departTime: DateTime(2026, 9, 30, 8),
      origin: '기점',
      destination: '학원',
      estDurationMin: 30,
      runStatus: RunStatus.idle,
      confirmed: false,
      confirmAt: DateTime(2026, 9, 30, 7, 30),
      startWindowFrom: DateTime(2026, 9, 30, 7, 50),
      startWindowTo: DateTime(2026, 9, 30, 8, 10),
      addedCount: 0,
      removedCount: 0,
      ackRequired: false,
    );
    await tester.pumpWidget(
      wrap([
        todayRunsProvider.overrideWith((ref) async => [run]),
        currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('출발 30분 전 확정 후 열립니다 (07:30)'), findsOneWidget);
  });

  testWidgets('확정된 회차에는 열리는 시각 안내가 없다', (tester) async {
    await tester.pumpWidget(
      wrap([
        todayRunsProvider.overrideWith((ref) async => [confirmedRun()]),
        currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('확정 후 열립니다'), findsNothing);
  });
}
