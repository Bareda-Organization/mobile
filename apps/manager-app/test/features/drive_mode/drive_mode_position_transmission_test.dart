import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/constants/position_constants.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_screen.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/position/data/models/position_request.dart';
import 'package:manager_app/features/position/domain/position_repository.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';

/// 시각을 고정하는 가짜 시계 — `drive_mode_screen_test.dart` 와 같은 패턴.
class _FixedClock implements Clock {
  const _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

/// 항상 같은 좌표 스냅샷을 돌려주는 가짜 위치 소스. `recordedAt` 을
/// 시험이 고정하는 "지금"과 **다른 값**으로 둬서, 화면이 전송 시각을
/// 새로 채우는 것이 아니라 이 값을 그대로 옮기는지 구별한다(§4.12).
class _FakePositionSource implements PositionSource {
  _FakePositionSource(this._sample);

  final PositionSample _sample;
  int callCount = 0;

  @override
  PositionSample? sample() {
    callCount++;
    return _sample;
  }
}

/// 실제 서버를 부르지 않고 `sendPosition` 호출을 그대로 기록하는 가짜
/// 리포지토리 — 타이머가 실제로 도는지, 몇 번 도는지를 이걸로 잰다.
class _RecordingPositionRepository implements PositionRepository {
  final List<PositionRequest> calls = [];

  @override
  Future<void> sendPosition({
    required String runId,
    required PositionRequest request,
  }) async {
    calls.add(request);
  }
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

ManagerRun _managerRun({
  required RunStatus runStatus,
  required DateTime now,
}) {
  return ManagerRun(
    runId: 'run-1',
    busNo: '3호차',
    direction: RunDirection.toAcademy,
    departTime: now.add(const Duration(minutes: 10)),
    origin: '기점',
    destination: '학원',
    estDurationMin: 30,
    runStatus: runStatus,
    confirmed: true,
    startWindowFrom: now.subtract(const Duration(minutes: 5)),
    startWindowTo: now.add(const Duration(minutes: 5)),
    addedCount: 0,
    removedCount: 0,
    ackRequired: false,
  );
}

void main() {
  const runId = 'run-1';
  final now = DateTime(2026, 9, 12, 8);
  // 시험이 고정하는 "지금"과 다른 값 — 서버로 나가는 recorded_at 이
  // clockProvider(전송 시각)가 아니라 [PositionSample.recordedAt](단말
  // 측정 시각)에서 온 것인지 이 값 하나로 구별한다.
  final recordedAt = DateTime(2020);

  List<Override> baseOverrides({
    required UserRole role,
    required RunStatus runStatus,
    required _FakePositionSource positionSource,
    required _RecordingPositionRepository positionRepository,
  }) => [
    clockProvider.overrideWithValue(_FixedClock(now)),
    currentUserRoleProvider.overrideWith((ref) => role),
    selectedRunIdProvider.overrideWith((ref) => runId),
    driveModeRunProvider.overrideWithValue(
      _managerRun(runStatus: runStatus, now: now),
    ),
    driveModeRosterProvider.overrideWith((ref) async => _emptyRoster),
    positionSourceProvider.overrideWithValue(positionSource),
    positionRepositoryProvider.overrideWithValue(positionRepository),
  ];

  testWidgets('기사·이동 중 상태면 PositionConstants.transmissionInterval 주기로 위치를 전송한다', (
    tester,
  ) async {
    final source = _FakePositionSource(
      PositionSample(lat: 37.5, lng: 127, recordedAt: recordedAt),
    );
    final repository = _RecordingPositionRepository();
    const interval = PositionConstants.transmissionInterval;

    await tester.pumpWidget(
      _wrap(
        const DriveModeScreen(),
        baseOverrides(
          role: UserRole.driver,
          runStatus: RunStatus.moving,
          positionSource: source,
          positionRepository: repository,
        ),
      ),
    );
    await tester.pump();

    // 주기가 지나기 전에는 아직 전송이 없어야 "0초마다"가 아님을
    // 함께 확인한다. 값을 상수에서 읽으므로 주기가 바뀌어도 이 시험은
    // 그대로 유효하다 — 값 자체를 고정하는 것은 아래 별도 시험의 몫.
    await tester.pump(interval - const Duration(milliseconds: 1));
    expect(repository.calls, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    expect(repository.calls, hasLength(1));
    // 서버로 나가는 recorded_at 은 전송 시각(clockProvider 의 `now`)이
    // 아니라 위치 소스가 준 단말 측정 시각 그대로다.
    expect(repository.calls.single.recordedAt, recordedAt);

    // 주기 타이머임을 확인 — 한 주기를 더 지나면 두 번째 전송이 있다.
    await tester.pump(interval);
    expect(repository.calls, hasLength(2));
  });

  test('위치 전송 주기 상수는 2초로 고정한다 (2026-09-14 사용자 결정)', () {
    // ⚠ 값 자체를 하드코딩해 대조한다 — 위 위젯 시험처럼 상수를 그대로
    // 읽어 쓰면 상수가 조용히 바뀌어도 아무 시험도 잡지 못한다. 방송량이
    // 이 값에 산술적으로 비례하므로(COMMON-B2 §2), 바뀌면 이 시험이
    // 먼저 깨져 리뷰를 강제해야 한다.
    expect(
      PositionConstants.transmissionInterval,
      const Duration(seconds: 2),
    );
  });

  testWidgets('동승자면 이동 중이어도 위치를 전송하지 않는다', (tester) async {
    final source = _FakePositionSource(
      PositionSample(lat: 37.5, lng: 127, recordedAt: recordedAt),
    );
    final repository = _RecordingPositionRepository();

    await tester.pumpWidget(
      _wrap(
        const DriveModeScreen(),
        baseOverrides(
          role: UserRole.escort,
          runStatus: RunStatus.moving,
          positionSource: source,
          positionRepository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));

    expect(repository.calls, isEmpty);
  });

  testWidgets('기사여도 이동 중이 아니면 위치를 전송하지 않는다', (tester) async {
    final source = _FakePositionSource(
      PositionSample(lat: 37.5, lng: 127, recordedAt: recordedAt),
    );
    final repository = _RecordingPositionRepository();

    await tester.pumpWidget(
      _wrap(
        const DriveModeScreen(),
        baseOverrides(
          role: UserRole.driver,
          runStatus: RunStatus.confirmed,
          positionSource: source,
          positionRepository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));

    expect(repository.calls, isEmpty);
  });
}
