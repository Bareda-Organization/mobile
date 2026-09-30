import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

/// 시각을 고정하는 가짜 시계.
class _FixedClock implements Clock {
  const _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

/// 권한·서비스 상태를 시험이 바꿀 수 있는 가짜 위치 소스. [recheck] 를 불러야만 새 값을 반영한다 —
/// 실제 구현이 플랫폼에 다시 물어야 [availability] 가 바뀌는 것과 같다. 스트림은 켜지 않는다.
class _SwitchablePositionSource implements PositionSource {
  _SwitchablePositionSource(this.current);

  /// 기기 설정의 현재 상태 — 시험이 바꾼다. [recheck] 가 불려야 [availability] 에 보인다.
  PositionAvailability current;
  PositionAvailability _seen = PositionAvailability.available;
  int startCalls = 0;

  @override
  PositionAvailability get availability => _seen;

  @override
  Future<void> recheck() async => _seen = current;

  @override
  PositionSample? sample() => null;

  @override
  void start() => startCalls++;

  @override
  void stop() {}

  @override
  Future<PositionSample?> sampleOnce({
    Duration timeout = const Duration(seconds: 5),
  }) async => null;
}

const _emptyRoster = RosterResponse(
  runId: 'run-1',
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  counts: RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
  stops: [],
);

ManagerRun _confirmedRun(DateTime now) => ManagerRun(
  runId: 'run-1',
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  departTime: now.add(const Duration(minutes: 10)),
  origin: '기점',
  destination: '학원',
  estDurationMin: 30,
  runStatus: RunStatus.confirmed,
  confirmed: true,
  startWindowFrom: now.subtract(const Duration(minutes: 5)),
  startWindowTo: now.add(const Duration(minutes: 5)),
  addedCount: 0,
  removedCount: 0,
  ackRequired: false,
  roleInRun: UserRole.driver,
);

/// M2-02(F06-03 나머지) — 운행 시작 전(`confirmed`)에도 위치 권한·서비스가 꺼져 있으면 기사에게 알린다.
/// 출발 뒤에야 송신 실패를 아는 것을 막는다. 알리려고 스트림(포그라운드 서비스 알림)을 켜지는 않는다.
void main() {
  const permissionMessage = '위치 권한이 없어 위치를 보낼 수 없습니다';
  final now = DateTime(2026, 9, 12, 8);

  Future<_SwitchablePositionSource> pump(
    WidgetTester tester,
    PositionAvailability initial,
  ) async {
    final source = _SwitchablePositionSource(initial);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(_FixedClock(now)),
          currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
          selectedRunIdProvider.overrideWith((ref) => 'run-1'),
          driveModeRunProvider.overrideWithValue(_confirmedRun(now)),
          todayRunsProvider.overrideWith((ref) async => [_confirmedRun(now)]),
          routeProvider.overrideWith(
            (ref) async => const RouteResponse(stops: []),
          ),
          driveModeRosterProvider.overrideWith((ref) async => _emptyRoster),
          positionSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(home: DriveModeScreen()),
      ),
    );
    await tester.pump();
    // 첫 확인이 끝나 배너가 그려질 시간.
    await tester.pump(PositionConstants.transmissionInterval);
    return source;
  }

  testWidgets('운행 시작 전에도 위치 권한이 없으면 배너로 알리고, 스트림은 켜지 않는다', (tester) async {
    final source = await pump(tester, PositionAvailability.permissionDenied);

    expect(find.textContaining(permissionMessage), findsOneWidget);
    expect(source.startCalls, 0);
  });

  testWidgets('설정에서 권한을 허용하면 앱을 다시 켜지 않아도 배너가 사라진다', (tester) async {
    final source = await pump(tester, PositionAvailability.permissionDenied);
    expect(find.textContaining(permissionMessage), findsOneWidget);

    source.current = PositionAvailability.available;
    await tester.pump(PositionConstants.transmissionInterval);

    expect(find.textContaining(permissionMessage), findsNothing);
  });

  testWidgets('작은 화면에서도 권한 배너가 아래 고정 [운행 시작] 버튼보다 위에 온다', (tester) async {
    // 본문이 스크롤돼야 하는 높이 — 지도(화면의 30%)·요약 카드 아래 배너가 접힌 곳에 놓이면 버튼에 잘린다.
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, PositionAvailability.permissionDenied);

    final bannerBottom = tester
        .getRect(find.textContaining(permissionMessage))
        .bottom;
    final buttonTop = tester
        .getRect(find.widgetWithText(BaraedaButton, '운행 시작'))
        .top;

    expect(bannerBottom, lessThanOrEqualTo(buttonTop));
  });

  testWidgets('권한이 정상이면 배너가 없다', (tester) async {
    await pump(tester, PositionAvailability.available);

    expect(find.textContaining(permissionMessage), findsNothing);
  });
}
