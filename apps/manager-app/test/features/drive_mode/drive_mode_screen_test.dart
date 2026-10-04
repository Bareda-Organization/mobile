import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_screen.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

/// 시각을 고정해 판정을 결정적으로 만드는 가짜 시계
/// ([clockProvider] override 대상, 이월 11 · Ruling 266).
class _FixedClock implements Clock {
  const new(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

/// 목표 9 검사용 대역 — `managerRunChannelProvider` 는 구체 클래스
/// `ManagerRunChannelController` 로 타입이 고정돼 있어 그 컨트롤러 자체를
/// 가짜로 바꿔치기할 수 없다(`roster_screen_test.dart`의 같은 이름 대역과
/// 동일한 이유). 대신 그 생성자가 유일하게 주입받는
/// `TokenStorage.readAccessToken()` 을 영원히 끝나지 않는 대기로 만들어
/// 실제 컨트롤러를 `ManagerChannelStatus.connecting` 에 고정시킨다.
class _NeverResolvingTokenStorage extends TokenStorage {
  new()
    : super(
        accessTokenKey: 'test_access_token',
        refreshTokenKey: 'test_refresh_token',
      );

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;
}

Widget _wrap(Widget child, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

/// 도착 처리 대상이 없는 빈 명단 — 이 파일은 "운행 시작" 버튼의 출발
/// 시간 창(±10분) 게이팅만 본다.
const _emptyRoster = RosterResponse(
  runId: 'run-1',
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  counts: RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
  stops: [],
);

/// 서버가 `START_WINDOW_CLOSED`(§4.4)로 막는 것과 같은 창을
/// [ManagerRun.startWindowFrom]·[startWindowTo] 로 미리 화면에서도
/// 판정한다 — 판정 기준 시각은 [clockProvider] 를 [_FixedClock] 으로
/// override 해 고정한다(이월 11 · Ruling 266, `DateTime.now()` 직접 호출
/// 금지).
ManagerRun _managerRun({
  required DateTime startWindowFrom,
  required DateTime startWindowTo,
}) {
  return ManagerRun(
    runId: 'run-1',
    busNo: '3호차',
    direction: RunDirection.toAcademy,
    departTime: startWindowFrom.add(const Duration(minutes: 10)),
    origin: '기점',
    destination: '학원',
    estDurationMin: 30,
    runStatus: RunStatus.confirmed,
    confirmed: true,
    startWindowFrom: startWindowFrom,
    startWindowTo: startWindowTo,
    addedCount: 0,
    removedCount: 0,
    ackRequired: false,
  );
}

void main() {
  const runId = 'run-1';

  // 운행 시작은 운행 준비 화면으로 옮겼다(`Ruling 799`) — 시작 가능 시간 판정 · 확인 창 · RUN_CANCELED 처리는
  // `run_ready_screen_test.dart` 가 같은 조건으로 문다.

  // 2026-09-23 — 노선 지도(M-04·M-09)는 기사 전용인데, 버튼이 동승자만 들어가는 명단 화면에만 있어서
  // 기사도 동승자도 닿지 못했다. 기사가 홈에서 들어오는 유일한 화면이 여기라 여기서 연다.
  testWidgets('지도의 [크게 보기] 를 누르면 노선 지도 화면으로 간다', (tester) async {
    final now = DateTime(2026, 9, 12, 8);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const DriveModeScreen()),
        GoRoute(
          path: AppRoutes.routeMap,
          builder: (_, _) => const Text('노선 지도 화면'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(_FixedClock(now)),
          selectedRunIdProvider.overrideWith((ref) => runId),
          driveModeRunProvider.overrideWithValue(
            _managerRun(
              startWindowFrom: now.subtract(const Duration(minutes: 5)),
              startWindowTo: now.add(const Duration(minutes: 5)),
            ),
          ),
          // R32 M1 — 운행 화면이 노선을 조회한다. 실제 서버로 나가지 않게 빈 노선으로 막는다.
          routeProvider.overrideWith(
            (ref) async => const RouteResponse(stops: []),
          ),
          driveModeRosterProvider.overrideWith((ref) async => _emptyRoster),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('노선 크게 보기'));
    await tester.pumpAndSettle();

    expect(find.text('노선 지도 화면'), findsOneWidget);
  });

  group('목표 9 — 연결 배너가 명단 상태와 무관하게 뜬다', () {
    const bannerTitle = '실시간 연결 중';

    testWidgets('명단이 로딩 중이어도 배너가 뜬다', (tester) async {
      final now = DateTime(2026, 9, 12, 8);
      final completer = Completer<RosterResponse>();
      await tester.pumpWidget(
        _wrap(const DriveModeScreen(), [
          clockProvider.overrideWithValue(_FixedClock(now)),
          selectedRunIdProvider.overrideWith((ref) => runId),
          driveModeRunProvider.overrideWithValue(
            _managerRun(
              startWindowFrom: now.subtract(const Duration(minutes: 5)),
              startWindowTo: now.add(const Duration(minutes: 5)),
            ),
          ),
          // R32 M1 — 운행 화면이 노선을 조회한다. 실제 서버로 나가지 않게 빈 노선으로 막는다.
          routeProvider.overrideWith(
            (ref) async => const RouteResponse(stops: []),
          ),
          driveModeRosterProvider.overrideWith((ref) => completer.future),
          tokenStorageProvider.overrideWithValue(
            _NeverResolvingTokenStorage(),
          ),
        ]),
      );
      await tester.pump();

      expect(find.text(bannerTitle), findsOneWidget);
    });

    testWidgets('명단에 데이터가 있어도 배너가 뜬다', (tester) async {
      final now = DateTime(2026, 9, 12, 8);
      await tester.pumpWidget(
        _wrap(const DriveModeScreen(), [
          clockProvider.overrideWithValue(_FixedClock(now)),
          selectedRunIdProvider.overrideWith((ref) => runId),
          driveModeRunProvider.overrideWithValue(
            _managerRun(
              startWindowFrom: now.subtract(const Duration(minutes: 5)),
              startWindowTo: now.add(const Duration(minutes: 5)),
            ),
          ),
          // R32 M1 — 운행 화면이 노선을 조회한다. 실제 서버로 나가지 않게 빈 노선으로 막는다.
          routeProvider.overrideWith(
            (ref) async => const RouteResponse(stops: []),
          ),
          driveModeRosterProvider.overrideWith((ref) async => _emptyRoster),
          tokenStorageProvider.overrideWithValue(
            _NeverResolvingTokenStorage(),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text(bannerTitle), findsOneWidget);
    });

    testWidgets('명단이 비어 있어도 배너가 뜬다', (tester) async {
      final now = DateTime(2026, 9, 12, 8);
      const empty = RosterResponse(
        runId: 'run-1',
        busNo: '3호차',
        direction: RunDirection.toAcademy,
        counts: RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
        stops: [],
      );
      await tester.pumpWidget(
        _wrap(const DriveModeScreen(), [
          clockProvider.overrideWithValue(_FixedClock(now)),
          selectedRunIdProvider.overrideWith((ref) => runId),
          driveModeRunProvider.overrideWithValue(
            _managerRun(
              startWindowFrom: now.subtract(const Duration(minutes: 5)),
              startWindowTo: now.add(const Duration(minutes: 5)),
            ),
          ),
          // R32 M1 — 운행 화면이 노선을 조회한다. 실제 서버로 나가지 않게 빈 노선으로 막는다.
          routeProvider.overrideWith(
            (ref) async => const RouteResponse(stops: []),
          ),
          driveModeRosterProvider.overrideWith((ref) async => empty),
          tokenStorageProvider.overrideWithValue(
            _NeverResolvingTokenStorage(),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text(bannerTitle), findsOneWidget);
    });
  });
}
