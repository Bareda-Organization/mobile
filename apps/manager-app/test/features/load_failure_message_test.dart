import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/me_provider.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_screen.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/home/presentation/home_screen.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_screen.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/roster/presentation/roster_screen.dart';
import 'package:manager_app/features/route_map/presentation/route_map_screen.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';
import '../support/fake_notification_repository.dart';
import '../support/manager_run_fixture.dart';

/// R32 M8 — 불러오기에 실패했을 때 예외 원문(`Exception: …` · `Instance of …`)을 화면에 그대로
/// 보이지 않고, 다른 화면과 같은 쉬운 문구(`describeFailure`)로 보인다. 5개 화면 각 1건.
class _NeverResolvingTokenStorage extends TokenStorage {
  new()
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

const _rawDetail = 'raw-internal-detail-7f3a';

/// 실패한 provider 를 던지는 값 — [Failure] 는 Exception 이 아니라서 `Object` 로 던진다.
Never _fail(Object error) {
  // Failure 는 Exception/Error 를 상속하지 않아 only_throw_errors 에 걸린다(다른 시험의 같은 패턴).
  // ignore: only_throw_errors
  throw error;
}

void main() {
  final common = <Override>[
    tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
    positionSourceProvider.overrideWithValue(_NoSample()),
    selectedRunIdProvider.overrideWith((ref) => 'run-1'),
    currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
    // 머리줄 부제가 `/me` 를 읽는다 — 실제 서버로 나가지 않게 막는다.
    meProvider.overrideWith((ref) async => throw StateError('내 정보 미사용')),
    // 머리말 알림 배지가 실제 서버를 부르지 않게 한다(R46).
    notificationRepositoryProvider.overrideWithValue(
      FakeNotificationRepository(const []),
    ),
  ];
  final okRuns = todayRunsProvider.overrideWith(
    (ref) async => [managerRunFixture()],
  );

  final cases = <String, ({Widget screen, List<Override> failing})>{
    '홈': (
      screen: const ManagerHomeScreen(),
      failing: [todayRunsProvider.overrideWith((ref) => _fail(_rawDetail))],
    ),
    '운행': (
      screen: const DriveModeScreen(),
      failing: [
        okRuns,
        driveModeRosterProvider.overrideWith((ref) => _fail(_rawDetail)),
        routeProvider.overrideWith((ref) => _fail(_rawDetail)),
      ],
    ),
    '명단': (
      screen: const RosterScreen(),
      failing: [
        okRuns,
        rosterProvider.overrideWith((ref) => _fail(_rawDetail)),
      ],
    ),
    '노선 지도': (
      screen: const RouteMapScreen(),
      failing: [okRuns, routeProvider.overrideWith((ref) => _fail(_rawDetail))],
    ),
    '오프라인 대기열': (
      screen: const OfflineQueueScreen(),
      failing: [
        pendingRequestsProvider.overrideWith((ref) => _fail(_rawDetail)),
      ],
    ),
  };

  for (final entry in cases.entries) {
    testWidgets('${entry.key} — 실패해도 예외 원문을 보이지 않는다', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [...common, ...entry.value.failing],
          child: MaterialApp(home: entry.value.screen),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining(_rawDetail), findsNothing);
      expect(find.textContaining('불러오지 못했'), findsWidgets);
    });
  }

  // 홈은 시안대로 고정 문장("인터넷 연결을 확인하고…")을 보이므로 실패 문구 사상은 명단으로 문다.
  testWidgets('Failure 는 describeFailure 와 같은 문구로 보인다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          ...common,
          okRuns,
          rosterProvider.overrideWith((ref) => _fail(const NetworkFailure())),
        ],
        child: const MaterialApp(home: RosterScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('네트워크 상태를 확인해 주세요'), findsOneWidget);
  });
}
