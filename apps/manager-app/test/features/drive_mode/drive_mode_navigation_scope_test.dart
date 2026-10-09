import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_screen.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/navigation/data/kakao_navi_launcher.dart';
import 'package:manager_app/features/navigation/data/models/navigation_route.dart';
import 'package:manager_app/features/navigation/data/navigation_api.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

import '../../support/manager_run_fixture.dart';

/// 서버 흉내 — `scope=next` 면 다음 목적지 1곳, `remaining` 이면
/// 경유지 1곳 + 최종 목적지(API_SPEC §4.16).
class _ServerAdapter implements HttpClientAdapter {
  final scopes = <Object?>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    scopes.add(options.queryParameters['scope']);
    final isNext = options.queryParameters['scope'] == 'next';
    return ResponseBody.fromString(
      jsonEncode({
        'provider': 'kakao',
        'waypoints': isNext
            ? <Object>[]
            : [
                {'lat': 37.51, 'lng': 127.01, 'name': '1번', 'stop_id': 's1'},
              ],
        'destination': isNext
            ? {'lat': 37.51, 'lng': 127.01, 'name': '1번', 'stop_id': 's1'}
            : {'lat': 37.53, 'lng': 127.03, 'name': '학원', 'stop_id': 's9'},
        'truncated': false,
        'total_remaining_stops': 2,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

/// 카카오내비 경계의 가짜 — 넘겨받은 경로를 기록한다. 실제 앱을 열지 않는다.
class _RecordingLauncher implements KakaoNaviLauncher {
  final launched = <NavigationRoute>[];

  @override
  Future<NaviLaunchResult> launch(NavigationRoute route) async {
    launched.add(route);
    return NaviLaunchResult.launched;
  }

  @override
  Uri get installUri => Uri.parse('https://navi.example/install');
}

class _NeverResolvingTokenStorage extends TokenStorage {
  new()
    : super(accessTokenKey: 'a', refreshTokenKey: 'r');

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;
}

void main() {
  /// 실제 저장소·API 를 거치게 서버 어댑터만 가짜로 두고 화면을 띄운다 — 화면이 고른 범위가
  /// 서버 질의와 카카오내비 요청까지 그대로 이어지는지 본다.
  Future<({_ServerAdapter server, _RecordingLauncher launcher})> pumpDrive(
    WidgetTester tester,
  ) async {
    final server = _ServerAdapter();
    final launcher = _RecordingLauncher();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
          kakaoNaviAppKeyProvider.overrideWithValue('KEY-1'),
          navigationApiProvider.overrideWithValue(
            NavigationApi(
              dio: Dio(BaseOptions(baseUrl: 'http://x/api/v1'))
                ..httpClientAdapter = server,
            ),
          ),
          kakaoNaviLauncherProvider.overrideWithValue(launcher),
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
                RosterStop(stopId: 's9', seq: 2, name: '학원', students: []),
              ],
            ),
          ),
        ],
        child: const MaterialApp(home: DriveModeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    return (server: server, launcher: launcher);
  }

  // 지도 위 두 단추로 범위를 바로 고른다 — 시트 없음(Ruling 570).
  group('UF-D-02 길안내 범위 선택', () {
    testWidgets('[다음 목적지] 는 scope=next 로 묻고 목적지 1곳만 내비에 넘긴다', (tester) async {
      final harness = await pumpDrive(tester);

      await tester.tap(find.text('다음 목적지'));
      await tester.pumpAndSettle();

      expect(harness.server.scopes, ['next']);
      final request = kakaoNaviRequest(harness.launcher.launched.single);
      expect(request.destination.name, '1번');
      expect(request.viaList, isEmpty);
    });

    testWidgets('[남은 전 구간] 은 scope=remaining 으로 묻고 경유지까지 내비에 넘긴다', (
      tester,
    ) async {
      final harness = await pumpDrive(tester);

      await tester.tap(find.text('남은 전 구간'));
      await tester.pumpAndSettle();

      expect(harness.server.scopes, ['remaining']);
      final request = kakaoNaviRequest(harness.launcher.launched.single);
      expect(request.destination.name, '학원');
      expect(request.viaList.map((p) => p.name), ['1번']);
    });
  });
}
