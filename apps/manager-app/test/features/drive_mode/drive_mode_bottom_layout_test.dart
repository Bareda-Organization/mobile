import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
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
import 'package:manager_app/features/drive_mode/presentation/widgets/bottom_notice_stack.dart';
import 'package:manager_app/features/drive_mode/presentation/widgets/drive_map_panel.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/navigation/data/kakao_navi_launcher.dart';
import 'package:manager_app/features/navigation/data/models/navigation_route.dart';
import 'package:manager_app/features/navigation/data/models/navigation_scope.dart';
import 'package:manager_app/features/navigation/domain/navigation_repository.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

import '../../support/manager_run_fixture.dart';

class _OkArrive implements DriveModeRepository {
  @override
  Future<ArriveStopResult> arriveStop({
    required String runId,
    required String stopId,
  }) async => ArriveStopResult(
    arrivedAt: DateTime(2026, 10, 1, 8, 5),
    isFinal: false,
    runStatus: RunStatus.moving,
    finishPending: false,
    remaining: const [],
  );

  @override
  Future<StartRunResult> startRun(String runId) => throw UnimplementedError();
}

class _OneStopNavigation implements NavigationRepository {
  @override
  Future<NavigationRoute> fetch(String runId, NavigationScope scope) async =>
      const NavigationRoute(
        provider: 'kakao',
        waypoints: [],
        destination: NavigationPoint(lat: 37.5, lng: 127, name: '학원'),
        truncated: false,
        totalRemainingStops: 1,
      );
}

/// 설치돼 있지 않다고 답하는 카카오내비 경계 — 미설치 배너를 띄운다.
class _NotInstalledLauncher implements KakaoNaviLauncher {
  @override
  Future<NaviLaunchResult> launch(NavigationRoute route) async =>
      NaviLaunchResult.notInstalled;

  @override
  Uri get installUri => Uri.parse('https://navi.example/install');
}

class _DeniedSource implements PositionSource {
  @override
  PositionAvailability get availability =>
      PositionAvailability.permissionDenied;

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

class _NeverResolvingTokenStorage extends TokenStorage {
  new()
    : super(accessTokenKey: 'a', refreshTokenKey: 'r');

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;
}

void main() {
  final errors = <FlutterErrorDetails>[];

  /// 화면이 그리는 동안 보고하는 오류를 시험이 직접 받는다. 시험 바인딩이 본문 시작 때 핸들러를
  /// 덮어쓰므로 본문 안에서 걸고, 판정(`expect`)이 실패할 때 바인딩과 얽히지 않게 그린 직후 돌려놓는다.
  Future<void> collectErrorsWhile(Future<void> Function() body) async {
    errors.clear();
    final original = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      await body();
    } finally {
      FlutterError.onError = original;
    }
  }

  /// 알림이 쌓인 가장 나쁜 운행 화면 — 위치 권한 · 카카오내비 미설치.
  Future<void> pumpCrowded(
    WidgetTester tester, {
    required Size size,
    required double textScale,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await collectErrorsWhile(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(
              _NeverResolvingTokenStorage(),
            ),
            positionSourceProvider.overrideWithValue(_DeniedSource()),
            kakaoNaviAppKeyProvider.overrideWithValue('KEY-1'),
            navigationRepositoryProvider.overrideWithValue(
              _OneStopNavigation(),
            ),
            kakaoNaviLauncherProvider.overrideWithValue(
              _NotInstalledLauncher(),
            ),
            settingsOpenerProvider.overrideWithValue((page) async => true),
            routeProvider.overrideWith(
              (ref) async => const RouteResponse(stops: []),
            ),
            selectedRunIdProvider.overrideWith((ref) => 'run-1'),
            currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
            todayRunsProvider.overrideWith(
              (ref) async => [managerRunFixture(status: RunStatus.moving)],
            ),
            driveModeRosterProvider.overrideWith(
              (ref) async => const RosterResponse(
                runId: 'run-1',
                busNo: '3호차',
                direction: RunDirection.toAcademy,
                counts: RosterCounts(
                  boarded: 0,
                  waiting: 0,
                  noShow: 0,
                  absentN: 0,
                ),
                stops: [
                  RosterStop(stopId: 's1', seq: 1, name: '1번', students: []),
                  RosterStop(stopId: 's2', seq: 2, name: '2번', students: []),
                  RosterStop(stopId: 's3', seq: 3, name: '3번', students: []),
                ],
              ),
            ),
            driveModeRepositoryProvider.overrideWithValue(_OkArrive()),
          ],
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
      await tester.pump(const Duration(seconds: 2));
      // 지도 위 [다음 목적지] 단추를 바로 누른다(시트 없음, Ruling 570). 큰 글자에서는 스크롤 밖에 있을 수 있어 보이게 한다.
      await tester.ensureVisible(find.text('다음 목적지'));
      await tester.pump();
      await tester.tap(find.text('다음 목적지'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('도착 처리'));
      await tester.pump();
      await tester.pump();
      // 도착 처리 토스트가 4초 뒤 사라지는 타이머와 사라지는 움직임까지 흘려 보낸다.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('알림이 여럿이면 가장 중요한 한 건만 보이고 나머지는 눌러야 펼쳐진다', (tester) async {
    await pumpCrowded(tester, size: const Size(375, 750), textScale: 1);

    // 위치 송신 불가(조작이 막힌 것)가 먼저, 카카오내비 미설치는 접혀 있다.
    // 도착 처리 결과는 알림이 아니라 토스트라 묶음에 들어오지 않는다(M6).
    expect(find.textContaining('위치 권한이 꺼져'), findsOneWidget);
    expect(find.textContaining('카카오내비가 설치돼'), findsNothing);

    await tester.tap(find.text('알림 1건 더 보기'));
    await tester.pump();

    expect(find.textContaining('카카오내비가 설치돼'), findsOneWidget);
    expect(find.text('알림 접기'), findsOneWidget);
  });

  for (final size in const [Size(360, 640), Size(375, 750)]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('하단 알림이 쌓여도 [도착 처리] 가 보이고 지도 영역이 남는다 '
          '(${size.width.toInt()}×${size.height.toInt()} · 글자 $scale배)', (
        tester,
      ) async {
        await pumpCrowded(tester, size: size, textScale: scale);

        final button = tester.getRect(
          find.widgetWithText(BaraedaButton, '도착 처리'),
        );
        final scroll = tester.getRect(find.byType(SingleChildScrollView).first);
        final noticeScroll = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(BottomNoticeStack),
            matching: find.byType(Scrollable),
          ),
        );

        // [도착 처리] 는 화면 안에 있고, 위쪽 스크롤 영역과 겹치지 않는다.
        expect(button.top, greaterThanOrEqualTo(scroll.bottom));
        expect(button.bottom, lessThanOrEqualTo(size.height));
        // 위쪽 스크롤 영역이 지도 패널의 최소 높이 이상으로 남는다 — 알림이 쌓여도 지도가 덮이지 않는다.
        expect(scroll.height, greaterThanOrEqualTo(DriveMapPanel.minHeight));
        // 기본 글자 크기에서는 가장 중요한 알림이 잘리지 않는다(큰 글자에서는 알림 안에서 스크롤한다).
        if (scale == 1.0) {
          expect(noticeScroll.position.maxScrollExtent, 0);
        }
        // 어떤 넘침도 없다 — 공용 `RunSummaryCard` 의 큰 글자 가로 넘침
        // (R46-FUMGR `Ruling 573`)을 고친 뒤로 이 시험이 허용하던 예외를
        // 걷었다(R46-LAST `Ruling 582`).
        expect(
          errors.map((e) => e.toString()).toList(),
          isEmpty,
        );
      });
    }
  }
}
