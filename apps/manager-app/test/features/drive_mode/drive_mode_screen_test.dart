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
import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
import 'package:manager_app/features/drive_mode/data/models/start_run_result.dart';
import 'package:manager_app/features/drive_mode/domain/drive_mode_repository.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_screen.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';

/// M4 — `_startRun` 이 `Failure` 를 어떻게 다루는지만 보는 시험용 대역.
/// `arriveStop` 은 이 파일의 시험 대상이 아니다.
class _FakeDriveModeRepository implements DriveModeRepository {
  _FakeDriveModeRepository({this.startFailure});

  final Failure? startFailure;

  @override
  Future<StartRunResult> startRun(String runId) async {
    // Failure 는 의도적으로 Exception/Error 를 상속하지 않는다
    // (roster_screen_test.dart 의 같은 패턴 주석 참고).
    // ignore: only_throw_errors
    if (startFailure != null) throw startFailure!;
    return StartRunResult(
      runStatus: RunStatus.moving,
      startedAt: DateTime(2026, 9, 12, 8),
    );
  }

  @override
  Future<ArriveStopResult> arriveStop({
    required String runId,
    required String stopId,
  }) => throw UnimplementedError('이 파일의 시험 대상이 아니다');
}

/// 시각을 고정해 판정을 결정적으로 만드는 가짜 시계
/// ([clockProvider] override 대상, 이월 11 · Ruling 266).
class _FixedClock implements Clock {
  const _FixedClock(this._now);

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
  _NeverResolvingTokenStorage()
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

  testWidgets('출발 시간 창 안이면 운행 시작 버튼을 보여준다', (tester) async {
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
        driveModeRosterProvider.overrideWith((ref) async => _emptyRoster),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('운행 시작'), findsOneWidget);
    expect(find.text('운행 시작 가능 시간(출발 ±10분)이 아닙니다'), findsNothing);
  });

  testWidgets('출발 시간 창 밖이면 운행 시작 버튼 대신 안내 문구를 보여준다', (tester) async {
    final now = DateTime(2026, 9, 12, 8);
    await tester.pumpWidget(
      _wrap(const DriveModeScreen(), [
        clockProvider.overrideWithValue(_FixedClock(now)),
        selectedRunIdProvider.overrideWith((ref) => runId),
        driveModeRunProvider.overrideWithValue(
          _managerRun(
            startWindowFrom: now.add(const Duration(minutes: 20)),
            startWindowTo: now.add(const Duration(minutes: 40)),
          ),
        ),
        driveModeRosterProvider.overrideWith((ref) async => _emptyRoster),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('운행 시작'), findsNothing);
    expect(find.text('운행 시작 가능 시간(출발 ±10분)이 아닙니다'), findsOneWidget);
  });

  // M4(Ruling 340) — 취소된 회차(§4.1 목록에서도 제외)에 운행 시작을
  // 시도하면 서버가 409 RUN_CANCELED 로 거절한다. 문구를 보여주는 것에서
  // 그치지 않고 §4.1 오늘 회차 목록을 다시 불러와야 취소된 카드가 화면에
  // 남지 않는다.
  testWidgets('409 RUN_CANCELED 면 문구 + 오늘 회차 목록을 다시 불러온다', (tester) async {
    final now = DateTime(2026, 9, 12, 8);
    var todayRunsFetchCount = 0;
    final fakeRepo = _FakeDriveModeRepository(
      startFailure: const ApiFailure(
        statusCode: 409,
        code: 'RUN_CANCELED',
        message: '취소된 회차입니다',
      ),
    );

    await tester.pumpWidget(
      _wrap(const DriveModeScreen(), [
        clockProvider.overrideWithValue(_FixedClock(now)),
        selectedRunIdProvider.overrideWith((ref) => runId),
        // `driveModeRunProvider` 를 직접 override 하지 않는다 — 실제
        // 구현이 `todayRunsProvider` 를 읽어 유도하는 provider라, 여기서
        // 직접 값을 박으면 무효화가 이 provider 에 닿는지 확인할 수 없다.
        driveModeRosterProvider.overrideWith((ref) async => _emptyRoster),
        driveModeRepositoryProvider.overrideWithValue(fakeRepo),
        todayRunsProvider.overrideWith((ref) async {
          todayRunsFetchCount++;
          return [
            _managerRun(
              startWindowFrom: now.subtract(const Duration(minutes: 5)),
              startWindowTo: now.add(const Duration(minutes: 5)),
            ),
          ];
        }),
      ]),
    );
    await tester.pumpAndSettle();
    expect(todayRunsFetchCount, 1);

    await tester.tap(find.text('운행 시작'));
    await tester.pumpAndSettle();

    expect(find.text('취소된 회차입니다'), findsOneWidget);
    expect(todayRunsFetchCount, 2);
  });

  // 2026-09-23 — 노선 지도(M-04·M-09)는 기사 전용인데, 버튼이 동승자만 들어가는 명단 화면에만 있어서
  // 기사도 동승자도 닿지 못했다. 기사가 홈에서 들어오는 유일한 화면이 여기라 여기서 연다.
  testWidgets('노선 지도 버튼을 누르면 노선 지도 화면으로 간다', (tester) async {
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
          driveModeRosterProvider.overrideWith((ref) async => _emptyRoster),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('노선 지도'));
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
