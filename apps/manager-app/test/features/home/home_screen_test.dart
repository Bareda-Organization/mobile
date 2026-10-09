import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/me_provider.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
import 'package:manager_app/features/drive_mode/data/models/start_run_result.dart';
import 'package:manager_app/features/drive_mode/domain/drive_mode_repository.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/home/presentation/home_screen.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';

import '../../support/fake_notification_repository.dart';
import '../../support/manager_run_fixture.dart';

/// 운행 시작 요청이 나가는지만 세는 가짜 — 홈은 시작을 요청하지 않는다(`Ruling 799`).
class _CountingDriveRepository implements DriveModeRepository {
  int startCalls = 0;

  @override
  Future<StartRunResult> startRun(String runId) async {
    startCalls++;
    return StartRunResult(
      runStatus: RunStatus.moving,
      startedAt: DateTime(2026, 10, 3, 12, 20),
    );
  }

  @override
  Future<SendOutcome<ArriveStopResult>> arriveStop({
    required String runId,
    required String stopId,
  }) => throw UnimplementedError('이 파일의 시험 대상이 아니다');
}

class _FixedClock implements Clock {
  const new(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

/// 홈 탭의 세 갈래(로딩 · 성공 · 실패)와 역할별 단추(§4.1, M-02·M-07)를 직접 무는 시험.
///
/// 이동 화면은 표식 문구만 그리는 가짜 라우트로 둔다 — 관심사는 "어느 경로로 넘어가는가" 하나다.
void main() {
  final now = DateTime(2026, 10, 3, 12, 14);
  final depart = DateTime(2026, 10, 3, 12, 20);

  GoRouter buildRouter() => GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const ManagerHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.runReady,
        builder: (context, state) => const Text('RUN_READY_MARKER'),
      ),
      GoRoute(
        path: AppRoutes.driveMode,
        builder: (context, state) => const Text('DRIVE_MODE_MARKER'),
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
        clockProvider.overrideWithValue(_FixedClock(now)),
        // 머리말 알림 배지가 실제 서버를 부르지 않게 한다(R46).
        notificationRepositoryProvider.overrideWithValue(
          FakeNotificationRepository(const []),
        ),
        meProvider.overrideWith(
          (ref) async => const MeResponse(
            accountId: '1',
            loginId: 'driverA2',
            name: '박정훈',
            phone: '010-0000-0000',
            role: AccountRole.driver,
            status: AccountStatus.active,
          ),
        ),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: buildRouter()),
    );
  }

  // ⚠ 2026-09-21 실측(학부모 앱에서 먼저 드러났다) — 서버 시각은 **UTC 순간**인데 화면이 그대로 벽시계로 읽어
  // KST 에서 **9시간 이른 시각**이 나왔다. 기대값을 `toLocal()` 로 계산하는 이유는 시험기의 표준시를 바꿀
  // 수단이 부재하기 때문이다 — UTC 기계에서는 무해하게 통과하고 KST 에서 문다.
  testWidgets('출발 시각을 기기 표준시로 보여준다', (tester) async {
    final departUtc = DateTime.utc(2026, 10, 3, 10, 40);
    await tester.pumpWidget(
      wrap([
        todayRunsProvider.overrideWith(
          (ref) async => [managerRunFixture(departTime: departUtc)],
        ),
        currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
      ]),
    );
    await tester.pumpAndSettle();

    final local = departUtc.toLocal();
    final expected =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    expect(find.text(expected), findsOneWidget);
  });

  testWidgets('로딩 중에는 뼈대를 보여준다', (tester) async {
    final neverCompletes = Completer<List<ManagerRun>>().future;
    await tester.pumpWidget(
      wrap([todayRunsProvider.overrideWith((ref) => neverCompletes)]),
    );
    await tester.pump();

    expect(find.byType(BaraedaSkeleton), findsWidgets);
  });

  testWidgets('불러오기 실패 시 실패 안내와 [다시 시도] 를 보여준다', (tester) async {
    await tester.pumpWidget(
      wrap([
        todayRunsProvider.overrideWith(
          (ref) async => throw Exception('네트워크 오류'),
        ),
        currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('오늘 운행을 불러오지 못했어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('오늘 배정된 운행이 없으면 안내를 보여준다', (tester) async {
    await tester.pumpWidget(
      wrap([
        todayRunsProvider.overrideWith((ref) async => <ManagerRun>[]),
        currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('오늘 배정된 운행이 없어요'), findsOneWidget);
  });

  // G2 — 홈의 주 단추는 운행 준비로 가고, 홈에서는 운행 시작 요청이 나가지 않는다(`Ruling 799`).
  testWidgets('기사 홈의 [운행 준비하기] 는 운행 준비 화면으로 가고 시작 요청은 없다', (tester) async {
    final repo = _CountingDriveRepository();
    await tester.pumpWidget(
      wrap([
        todayRunsProvider.overrideWith(
          (ref) async => [
            managerRunFixture(
              departTime: depart,
              riderCount: 14,
              stopCount: 6,
              absentCount: 2,
            ),
          ],
        ),
        currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
        driveModeRepositoryProvider.overrideWithValue(repo),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('운행 준비하기'));
    await tester.pumpAndSettle();

    expect(find.text('RUN_READY_MARKER'), findsOneWidget);
    expect(find.text('DRIVE_MODE_MARKER'), findsNothing);
    expect(repo.startCalls, 0, reason: '시작은 운행 준비 화면의 확인 창 뒤에만 나간다');
  });

  testWidgets('동승자 홈에는 [운행 준비하기] 가 없고 [명단 열기] 가 명단으로 간다', (tester) async {
    await tester.pumpWidget(
      wrap([
        todayRunsProvider.overrideWith(
          (ref) async => [managerRunFixture(departTime: depart)],
        ),
        currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('운행 준비하기'), findsNothing);
    await tester.tap(find.text('명단 열기'));
    await tester.pumpAndSettle();

    expect(find.text('ROSTER_SCREEN_MARKER'), findsOneWidget);
  });

  testWidgets('역할을 모르면 운행 준비 단추를 그리지 않는다 — 모르면 막는 쪽이 기본값이다', (tester) async {
    await tester.pumpWidget(
      wrap([
        // currentUserRoleProvider 를 override 하지 않는다 — 기본값 null.
        todayRunsProvider.overrideWith(
          (ref) async => [managerRunFixture(departTime: depart)],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('운행 준비하기'), findsNothing);
  });

  // G2 — 확정 전 회차는 서버가 숫자를 세지 않아 `null` 이다. 0 으로 그리면 "탑승자 0명" 으로 읽힌다.
  testWidgets('숫자가 비어 있는(확정 전) 회차는 큰 카드의 숫자 줄을 통째로 숨긴다', (tester) async {
    await tester.pumpWidget(
      wrap([
        todayRunsProvider.overrideWith(
          (ref) async => [managerRunFixture(departTime: depart)],
        ),
        currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('탑승 예정'), findsNothing);
    expect(find.text('승하차지'), findsNothing);
    expect(find.text('시작 가능'), findsNothing);
  });

  testWidgets('숫자가 있으면 큰 카드에 탑승 예정 · 승하차지 · 시작 가능 시간이 보인다', (tester) async {
    await tester.pumpWidget(
      wrap([
        todayRunsProvider.overrideWith(
          (ref) async => [
            managerRunFixture(
              departTime: depart,
              riderCount: 14,
              stopCount: 6,
              absentCount: 2,
            ),
          ],
        ),
        currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('14명'), findsOneWidget);
    expect(find.text('탑승 예정'), findsOneWidget);
    expect(find.text('6곳'), findsOneWidget);
    expect(find.text('12:10~12:30'), findsOneWidget);
  });

  // R32 M9 — 확정 전 카드는 눌러도 반응이 없는데 이유를 알려 주지 않았다.
  testWidgets('확정 전 회차는 언제 열리는지 알려 준다', (tester) async {
    await tester.pumpWidget(
      wrap([
        todayRunsProvider.overrideWith(
          (ref) async => [
            ManagerRun(
              runId: 'run-2',
              busNo: '5호차',
              direction: RunDirection.toAcademy,
              departTime: DateTime(2026, 10, 3, 14, 40),
              origin: '기점',
              destination: '학원',
              runStatus: RunStatus.idle,
              confirmed: false,
              confirmAt: DateTime(2026, 10, 3, 14, 10),
              startWindowFrom: DateTime(2026, 10, 3, 14, 30),
              startWindowTo: DateTime(2026, 10, 3, 14, 50),
              addedCount: 0,
              removedCount: 0,
              ackRequired: false,
            ),
          ],
        ),
        currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('14:10 에 확정되면 열려요'), findsOneWidget);
    // 확정되지 않은 회차는 큰 카드가 되지 않는다.
    expect(find.text('명단 열기'), findsNothing);
  });

  // G2 — 로그아웃은 내 정보 탭 맨 아래에만 있다(`Ruling 826`). 홈 머리말에서 뺀다.
  testWidgets('홈에는 로그아웃이 없다', (tester) async {
    await tester.pumpWidget(
      wrap([
        todayRunsProvider.overrideWith(
          (ref) async => [managerRunFixture(departTime: depart)],
        ),
        currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('로그아웃'), findsNothing);
  });
}
