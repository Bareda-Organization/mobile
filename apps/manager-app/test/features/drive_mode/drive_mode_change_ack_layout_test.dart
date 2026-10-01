import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// 화면 확인(R46-SCREEN)에서 운행 화면의 `[변경 목록 확인]` 이 위쪽 스크롤 영역 경계에 반쯤 잘려 보였다.
/// 필수 확인 조작이라 하단 고정 영역(Ruling 571)에 두어, 스크롤과 무관하게
/// 첫 화면에 온전히 보여야 한다(R46-POLISH Ruling 596).
class _NeverResolvingTokenStorage extends TokenStorage {
  _NeverResolvingTokenStorage()
    : super(accessTokenKey: 'a', refreshTokenKey: 'r');

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;
}

/// 위치 권한이 없다고 답하는 위치 경계 — 하단 알림 한 건을 함께 띄워 가장 나쁜 조합(알림 + 확인 띠)을 만든다.
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

void main() {
  Future<void> pumpAckRequired(
    WidgetTester tester, {
    required Size size,
    required double textScale,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
          positionSourceProvider.overrideWithValue(_DeniedSource()),
          routeProvider.overrideWith(
            (ref) async => const RouteResponse(stops: []),
          ),
          selectedRunIdProvider.overrideWith((ref) => 'run-1'),
          currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
          todayRunsProvider.overrideWith(
            (ref) async => [
              managerRunFixture(status: RunStatus.moving, ackRequired: true),
            ],
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
              ],
            ),
          ),
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
  }

  for (final size in const [Size(402, 874), Size(375, 750), Size(360, 640)]) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('확인 띠가 떠도 [변경 목록 확인] 이 첫 화면에 온전히 보인다 '
          '(${size.width.toInt()}×${size.height.toInt()} · 글자 $scale배)', (
        tester,
      ) async {
        await pumpAckRequired(tester, size: size, textScale: scale);

        final button = tester.getRect(
          find.widgetWithText(BaraedaButton, '변경 목록 확인'),
        );

        // 화면 안에 있다.
        expect(button.top, greaterThanOrEqualTo(0));
        expect(button.bottom, lessThanOrEqualTo(size.height));
        // 스크롤 영역 안에 있다면 그 영역 경계에 잘리지 않아야 한다.
        for (final scrollable
            in find
                .ancestor(
                  of: find.widgetWithText(BaraedaButton, '변경 목록 확인'),
                  matching: find.byType(Scrollable),
                )
                .evaluate()) {
          final viewport = tester.getRect(find.byWidget(scrollable.widget));
          expect(button.top, greaterThanOrEqualTo(viewport.top));
          expect(button.bottom, lessThanOrEqualTo(viewport.bottom));
        }
      });
    }
  }
}
