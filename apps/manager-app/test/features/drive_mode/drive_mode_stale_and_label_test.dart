import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_screen.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

import '../../support/manager_run_fixture.dart';

/// R46 A — 기사 운행 화면. ① 명단 갱신이 실패해도 마지막 성공 명단과 [도착 처리] 가 남는다
/// ② 긴 승하차지 이름에도 버튼 동사(`도착 처리`)가 잘리지 않는다.
class _NeverResolvingTokenStorage extends TokenStorage {
  _NeverResolvingTokenStorage()
    : super(
        accessTokenKey: 'test_access_token',
        refreshTokenKey: 'test_refresh_token',
      );

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;
}

class _NoSample implements PositionSource {
  @override
  PositionAvailability get availability => PositionAvailability.available;

  @override
  PositionSample? sample() => null;

  @override
  Future<void> recheck() async {}

  @override
  void start() {}

  @override
  void stop() {}

  @override
  Future<PositionSample?> sampleOnce({
    Duration timeout = const Duration(seconds: 5),
  }) async => null;
}

const _longName = '서울 목동 신시가지 아파트 1단지 정문 앞 버스 정류장 (건너편 편의점 옆)';

RosterResponse _roster(String stopName) => RosterResponse(
  runId: 'run-1',
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  counts: const RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
  stops: [
    RosterStop(
      stopId: 's1',
      seq: 1,
      name: stopName,
      students: const [],
    ),
    const RosterStop(
      stopId: 's2',
      seq: 2,
      name: '학원',
      students: [],
    ),
  ],
);

Future<void> _pumpDrive(
  WidgetTester tester, {
  required FutureOr<RosterResponse> Function(int call) roster,
  double textScale = 1,
}) async {
  var calls = 0;
  final overrides = <Override>[
    tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
    positionSourceProvider.overrideWithValue(_NoSample()),
    routeProvider.overrideWith((ref) async => const RouteResponse(stops: [])),
    selectedRunIdProvider.overrideWith((ref) => 'run-1'),
    currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
    todayRunsProvider.overrideWith(
      (ref) async => [managerRunFixture(status: RunStatus.moving)],
    ),
    driveModeRosterProvider.overrideWith((ref) async => roster(calls++)),
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const DriveModeScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('R46 명단 갱신이 실패해도 마지막 명단의 [도착 처리] 가 남고 오류를 따로 알린다', (
    tester,
  ) async {
    await _pumpDrive(
      tester,
      roster: (call) {
        if (call == 0) return _roster('1번 승하차지');
        // Failure 는 Exception/Error 를 상속하지 않는다(다른 시험의 같은 패턴).
        // 위와 같은 이유.
        // ignore: only_throw_errors
        throw const NetworkFailure();
      },
    );
    expect(find.text('도착 처리'), findsOneWidget);

    ProviderScope.containerOf(
      tester.element(find.byType(DriveModeScreen)),
    ).invalidate(driveModeRosterProvider);
    await tester.pump();
    await tester.pump();

    expect(find.text('도착 처리'), findsOneWidget);
    expect(find.textContaining('불러오지 못했습니다'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('R46 처음부터 명단을 못 받으면 오류와 [다시 시도] 를 보인다', (tester) async {
    await _pumpDrive(
      tester,
      roster: (call) {
        // 위와 같은 이유.
        // ignore: only_throw_errors
        throw const NetworkFailure();
      },
    );

    expect(find.textContaining('불러오지 못했습니다'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('도착 처리'), findsNothing);
  });

  testWidgets('R46 긴 승하차지 이름·큰 글자에도 버튼 라벨은 도착 처리 그대로다', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pumpDrive(tester, roster: (_) => _roster(_longName), textScale: 1.3);

    expect(find.text('도착 처리'), findsOneWidget);
    // 이름은 버튼 밖 줄이다 — 두 줄까지 보이고 그 뒤만 줄인다.
    final name = tester.widget<Text>(find.textContaining('다음 승하차지'));
    expect(name.maxLines, 2);
    expect(tester.takeException(), isNull);
  });
}
