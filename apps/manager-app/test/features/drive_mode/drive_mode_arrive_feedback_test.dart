import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/launcher/device_launchers.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
import 'package:manager_app/features/drive_mode/data/models/start_run_result.dart';
import 'package:manager_app/features/drive_mode/domain/drive_mode_repository.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_screen.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/navigation/data/models/navigation_route.dart';
import 'package:manager_app/features/navigation/domain/navigation_repository.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

import '../../support/manager_run_fixture.dart';

/// 도착 처리 요청을 기록하고 항상 성공(마지막이 아닌 승하차지)으로 답한다.
class _ArriveRecorder implements DriveModeRepository {
  final arrivedStopIds = <String>[];

  @override
  Future<ArriveStopResult> arriveStop({
    required String runId,
    required String stopId,
  }) async {
    arrivedStopIds.add(stopId);
    return ArriveStopResult(
      arrivedAt: DateTime(2026, 10, 1, 8, 5),
      isFinal: false,
      runStatus: RunStatus.moving,
      finishPending: false,
      remaining: const [],
    );
  }

  @override
  Future<StartRunResult> startRun(String runId) => throw UnimplementedError();
}

/// 외부 내비 좌표열 — 호출을 세고 [truncated] 여부를 시험이 정한다.
class _FakeNavigationRepository implements NavigationRepository {
  _FakeNavigationRepository({this.truncated = false});

  final bool truncated;
  int calls = 0;

  @override
  Future<NavigationRoute> fetchRemaining(String runId) async {
    calls++;
    return NavigationRoute(
      provider: 'kakao',
      waypoints: const [
        NavigationPoint(lat: 37.51, lng: 127.01, name: '1번 승하차지'),
      ],
      destination: const NavigationPoint(
        lat: 37.53,
        lng: 127.03,
        name: '바른학원',
      ),
      truncated: truncated,
      truncatedReason: truncated ? '남은 승하차지가 많아 앞 2곳만 넘겼습니다' : null,
      totalRemainingStops: truncated ? 6 : 2,
    );
  }
}

/// 위치 권한·서비스 상태를 시험이 정하는 가짜 소스 — 좌표는 없다.
class _FixedAvailabilitySource implements PositionSource {
  _FixedAvailabilitySource(this.availability);

  @override
  final PositionAvailability availability;

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

/// 토큰을 영원히 기다려 운행 채널 연결이 시작되지 않게 한다 — 이 시험의 대상이 아니다.
class _NeverResolvingTokenStorage extends TokenStorage {
  _NeverResolvingTokenStorage()
    : super(accessTokenKey: 'a', refreshTokenKey: 'r');

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;
}

RosterStop _stop(int seq, {bool arrived = false}) => RosterStop(
  stopId: 's$seq',
  seq: seq,
  name: '$seq번 승하차지',
  arrivedAt: arrived ? DateTime(2026, 10, 1, 8, 1) : null,
  students: const [],
);

void main() {
  Future<
    ({
      _ArriveRecorder repository,
      List<String> settingsOpened,
      List<Uri> opened,
      _FakeNavigationRepository navigation,
    })
  >
  pumpDrive(
    WidgetTester tester, {
    List<RosterStop>? stops,
    PositionAvailability availability = PositionAvailability.available,
    String naviAppKey = '',
    bool openSucceeds = true,
    bool truncated = false,
  }) async {
    final repository = _ArriveRecorder();
    final navigation = _FakeNavigationRepository(truncated: truncated);
    final settingsOpened = <String>[];
    final opened = <Uri>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
          positionSourceProvider.overrideWithValue(
            _FixedAvailabilitySource(availability),
          ),
          kakaoNaviAppKeyProvider.overrideWithValue(naviAppKey),
          navigationRepositoryProvider.overrideWithValue(navigation),
          uriOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return openSucceeds;
          }),
          settingsOpenerProvider.overrideWithValue((page) async {
            settingsOpened.add(page.name);
            return true;
          }),
          routeProvider.overrideWith(
            (ref) async => const RouteResponse(stops: []),
          ),
          selectedRunIdProvider.overrideWith((ref) => 'run-1'),
          currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
          todayRunsProvider.overrideWith(
            (ref) async => [managerRunFixture(status: RunStatus.moving)],
          ),
          driveModeRosterProvider.overrideWith(
            (ref) async => RosterResponse(
              runId: 'run-1',
              busNo: '3호차',
              direction: RunDirection.toAcademy,
              counts: const RosterCounts(
                boarded: 0,
                waiting: 0,
                noShow: 0,
                absentN: 0,
              ),
              stops: stops ?? [_stop(1), _stop(2), _stop(3)],
            ),
          ),
          driveModeRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: DriveModeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    return (
      repository: repository,
      settingsOpened: settingsOpened,
      opened: opened,
      navigation: navigation,
    );
  }

  group('B2 #15 중간 승하차지 도착 처리 피드백', () {
    testWidgets('도착 처리에 성공하면 "N번 … 도착 처리됨" 을 알린다 (R46)', (tester) async {
      await pumpDrive(tester);

      await tester.tap(find.text('도착 처리'));
      await tester.pump();
      await tester.pump();

      expect(find.text('1번 1번 승하차지 도착 처리됨'), findsOneWidget);
    });

    testWidgets('성공 직후 2초 안의 두 번째 누름은 다음 승하차지를 처리하지 않는다 (R46)', (tester) async {
      final harness = await pumpDrive(tester);

      await tester.tap(find.text('도착 처리'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('도착 처리'), warnIfMissed: false);
      await tester.pump();

      expect(harness.repository.arrivedStopIds, ['s1']);

      // 잠금이 풀리면 다시 눌린다.
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.text('도착 처리'));
      await tester.pump();
      expect(harness.repository.arrivedStopIds, ['s1', 's1']);
    });
  });

  testWidgets('운행 화면 카드에도 출발 시각이 있다 (R46, B2 #25)', (tester) async {
    await pumpDrive(tester);

    // managerRunFixture 의 출발 시각은 2026-09-30 08:00.
    expect(find.text('출발 08:00'), findsOneWidget);
  });

  group('A #5 외부 내비(RUN-08)', () {
    testWidgets('카카오 앱 키가 없으면 [외부 내비] 버튼을 그리지 않는다 (R46)', (tester) async {
      await pumpDrive(tester);

      expect(find.text('외부 내비'), findsNothing);
    });

    testWidgets('키가 있으면 서버 좌표열로 카카오내비 주소를 만들어 연다 (R46)', (tester) async {
      final harness = await pumpDrive(tester, naviAppKey: 'KEY-1');

      await tester.tap(find.text('외부 내비'));
      await tester.pump();
      await tester.pump();

      expect(harness.navigation.calls, 1);
      expect(harness.opened, hasLength(1));
      final uri = harness.opened.single;
      expect(uri.scheme, 'kakaonavi-sdk');
      expect(uri.queryParameters['appkey'], 'KEY-1');
      expect(uri.queryParameters['param'], contains('바른학원'));
    });

    testWidgets('내비 앱이 열리지 않으면 이유를 알린다 (R46)', (tester) async {
      await pumpDrive(tester, naviAppKey: 'KEY-1', openSucceeds: false);

      await tester.tap(find.text('외부 내비'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('카카오내비를 열 수 없습니다'), findsOneWidget);
    });

    testWidgets('상한 때문에 잘렸으면 서버가 준 안내 문구를 보인다 (R46)', (tester) async {
      await pumpDrive(tester, naviAppKey: 'KEY-1', truncated: true);

      await tester.tap(find.text('외부 내비'));
      await tester.pump();
      await tester.pump();

      expect(find.text('남은 승하차지가 많아 앞 2곳만 넘겼습니다'), findsOneWidget);
    });
  });

  group('B2 #19 위치 권한 배너 [설정 열기]', () {
    testWidgets('권한이 없으면 [설정 열기] 가 앱 설정을 연다 (R46)', (tester) async {
      final harness = await pumpDrive(
        tester,
        availability: PositionAvailability.permissionDenied,
      );
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.text('설정 열기'));
      await tester.pump();

      expect(harness.settingsOpened, ['app']);
    });

    testWidgets('위치 서비스가 꺼져 있으면 [설정 열기] 가 위치 설정을 연다 (R46)', (tester) async {
      final harness = await pumpDrive(
        tester,
        availability: PositionAvailability.serviceDisabled,
      );
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.text('설정 열기'));
      await tester.pump();

      expect(harness.settingsOpened, ['location']);
    });

    testWidgets('정상이면 [설정 열기] 가 없다', (tester) async {
      await pumpDrive(tester);
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('설정 열기'), findsNothing);
    });
  });
}
