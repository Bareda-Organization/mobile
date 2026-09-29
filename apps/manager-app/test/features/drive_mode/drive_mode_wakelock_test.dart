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
import 'package:manager_app/core/wakelock/wakelock_port.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_screen.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/position/data/models/position_request.dart';
import 'package:manager_app/features/position/domain/position_repository.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

/// 호출 여부·횟수만 기록하는 가짜 포트 — `PositionSource` 가짜와 같은
/// 발상(F2). 실제 플랫폼 호출(`wakelock_plus`)은 이 시험에 등장하지 않는다.
class _RecordingWakelockPort implements WakelockPort {
  int enableCallCount = 0;
  int disableCallCount = 0;

  @override
  Future<void> enable() async {
    enableCallCount++;
  }

  @override
  Future<void> disable() async {
    disableCallCount++;
  }
}

class _FixedClock implements Clock {
  const _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

/// 항상 `null` 을 돌려주는 가짜 위치 소스 — 이 시험은 전송 자체가 아니라
/// wakelock 켜기·끄기 호출만 본다.
class _NoopPositionSource implements PositionSource {
  const _NoopPositionSource();

  @override
  void start() {}

  @override
  void stop() {}

  @override
  PositionSample? sample() => null;

  @override
  PositionAvailability get availability => PositionAvailability.available;

  @override
  Future<PositionSample?> sampleOnce({
    Duration timeout = const Duration(seconds: 5),
  }) async => null;
}

class _NoopPositionRepository implements PositionRepository {
  @override
  Future<void> sendPosition({
    required String runId,
    required PositionRequest request,
  }) async {}
}

Widget _wrap(Widget child, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

const _emptyRoster = RosterResponse(
  runId: 'run-1',
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  counts: RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
  stops: [],
);

void main() {
  const runId = 'run-1';
  final now = DateTime(2026, 9, 12, 8);

  ManagerRun run() => ManagerRun(
    runId: runId,
    busNo: '3호차',
    direction: RunDirection.toAcademy,
    departTime: now.add(const Duration(minutes: 10)),
    origin: '기점',
    destination: '학원',
    estDurationMin: 30,
    runStatus: RunStatus.moving,
    confirmed: true,
    startWindowFrom: now.subtract(const Duration(minutes: 5)),
    startWindowTo: now.add(const Duration(minutes: 5)),
    addedCount: 0,
    removedCount: 0,
    ackRequired: false,
  );

  List<Override> overridesFor(_RecordingWakelockPort port) => [
    clockProvider.overrideWithValue(_FixedClock(now)),
    currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
    selectedRunIdProvider.overrideWith((ref) => runId),
    driveModeRunProvider.overrideWithValue(run()),
    // R32 M1 — 운행 화면이 노선을 조회한다. 실제 서버로 나가지 않게 빈 노선으로 막는다.
    routeProvider.overrideWith((ref) async => const RouteResponse(stops: [])),
    driveModeRosterProvider.overrideWith((ref) async => _emptyRoster),
    positionSourceProvider.overrideWithValue(const _NoopPositionSource()),
    positionRepositoryProvider.overrideWithValue(_NoopPositionRepository()),
    wakelockPortProvider.overrideWithValue(port),
  ];

  testWidgets('운행 화면에 들어오면 화면 꺼짐 방지를 1회 켠다 (F2)', (tester) async {
    final port = _RecordingWakelockPort();

    await tester.pumpWidget(
      _wrap(const DriveModeScreen(), overridesFor(port)),
    );
    await tester.pump();

    expect(port.enableCallCount, 1);
    expect(port.disableCallCount, 0);
  });

  testWidgets('운행 화면이 dispose 되면 화면 꺼짐 방지를 1회 끈다 (F2)', (tester) async {
    final port = _RecordingWakelockPort();

    await tester.pumpWidget(
      _wrap(const DriveModeScreen(), overridesFor(port)),
    );
    await tester.pump();
    expect(port.enableCallCount, 1);

    // 화면을 완전히 다른 위젯으로 교체 — DriveModeScreen 의
    // State.dispose() 가 호출된다(`drive_mode_position_transmission_test.dart`
    // 와 같은 패턴).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(port.disableCallCount, 1);
  });
}
