import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/app.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/app/router.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/constants/position_constants.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
import 'package:manager_app/features/drive_mode/data/models/start_run_result.dart';
import 'package:manager_app/features/drive_mode/domain/drive_mode_repository.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/position/data/models/position_request.dart';
import 'package:manager_app/features/position/domain/position_repository.dart';
import 'package:manager_app/features/position/presentation/position_link.dart';
import 'package:manager_app/features/position/presentation/position_transmitter.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

import '../support/fake_token_storage.dart';
import '../support/manager_run_fixture.dart';

/// R33 M1 — 위치 송신은 화면이 아니라 앱 전역이다. 운행 중(`moving`)인 기사 회차면 어느 화면에서든
/// 2초마다 보내고, 운행 종료(마지막 도착 처리 응답)·로그아웃에 멈추며, 송신기는 하나다.
/// 앱 전체(`BaraedaManagerApp`)를 띄워 실제 라우터로 화면을 오간다.
class _FakeSource implements PositionSource {
  int startCalls = 0;
  int stopCalls = 0;

  PositionAvailability availabilityValue = PositionAvailability.available;

  @override
  PositionAvailability get availability => availabilityValue;

  @override
  PositionSample? sample() =>
      PositionSample(lat: 37.5, lng: 127, recordedAt: DateTime(2020));

  @override
  Future<void> recheck() async {}

  @override
  void start() => startCalls++;

  @override
  void stop() => stopCalls++;

  @override
  Future<PositionSample?> sampleOnce({
    Duration timeout = const Duration(seconds: 5),
  }) async => null;
}

class _RecordingPositionRepository implements PositionRepository {
  /// `true` 면 응답이 오지 않는 음영 구간을 흉내 낸다 — 요청이 끝나지 않는다.
  bool hang = false;

  /// 주면 전송이 이 오류로 실패한다 — 서버에 닿지 못하는 음영 구간.
  Failure? failWith;
  final List<PositionRequest> calls = [];

  @override
  Future<void> sendPosition({
    required String runId,
    required PositionRequest request,
  }) async {
    calls.add(request);
    if (hang) await Completer<void>().future;
    // `Failure` 는 이 저장소 전역에서 던지는 값이라 린트 예외를 둔다(다른 시험과 같다).
    // ignore: only_throw_errors
    if (failWith != null) throw failWith!;
  }
}

class _StubAuthRepository implements AuthRepository {
  @override
  Future<void> logout() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 마지막 승하차지 도착 처리 응답(`is_final`) — 하원 잔류로 서버 회차는 아직 `moving` 인 채다.
class _FinalArriveRepository implements DriveModeRepository {
  /// 주면 응답을 이 시점까지 붙잡는다 — 요청 중 화면이 닫히는 상황을 만든다.
  Completer<void>? gate;

  @override
  Future<ArriveStopResult> arriveStop({
    required String runId,
    required String stopId,
  }) async {
    await gate?.future;
    return _finalResult();
  }

  ArriveStopResult _finalResult() => ArriveStopResult(
    arrivedAt: DateTime(2026, 9, 30, 8, 30),
    isFinal: true,
    runStatus: RunStatus.moving,
    finishPending: true,
    remaining: const [],
  );

  @override
  Future<StartRunResult> startRun(String runId) => throw UnimplementedError();
}

const Duration _interval = PositionConstants.transmissionInterval;

void main() {
  late _FakeSource source;
  late _RecordingPositionRepository repository;
  late _FinalArriveRepository arriveRepository;

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    UserRole role = UserRole.driver,
    RunStatus status = RunStatus.moving,
    bool unavailable = false,
    List<ManagerRun>? runs,
  }) async {
    source = _FakeSource();
    if (unavailable) {
      source.availabilityValue = PositionAvailability.permissionDenied;
    }
    repository = _RecordingPositionRepository();
    arriveRepository = _FinalArriveRepository();
    final overrides = <Override>[
      tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
      currentUserRoleProvider.overrideWith((ref) => role),
      currentAccountStatusProvider.overrideWith(
        (ref) => AccountStatus.active,
      ),
      authRepositoryProvider.overrideWithValue(_StubAuthRepository()),
      driveModeRepositoryProvider.overrideWithValue(arriveRepository),
      selectedRunIdProvider.overrideWith((ref) => 'run-1'),
      todayRunsProvider.overrideWith(
        (ref) async =>
            runs ??
            [managerRunFixture(status: status, roleInRun: UserRole.driver)],
      ),
      routeProvider.overrideWith(
        (ref) async => const RouteResponse(stops: []),
      ),
      driveModeRosterProvider.overrideWith(
        (ref) async => const RosterResponse(
          runId: 'run-1',
          busNo: '3호차',
          direction: RunDirection.toAcademy,
          counts: RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
          stops: [
            RosterStop(
              stopId: 's1',
              seq: 1,
              name: '학원 앞',
              students: [],
            ),
          ],
        ),
      ),
      positionSourceProvider.overrideWithValue(source),
      positionRepositoryProvider.overrideWithValue(repository),
    ];
    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const BaraedaManagerApp()),
    );
    await tester.pumpAndSettle();
    // 컨테이너는 위젯 트리가 소유한다 — 시험이 끝나 트리가 걷힐 때 송신 타이머도 함께 정리된다.
    return ProviderScope.containerOf(
      tester.element(find.byType(BaraedaManagerApp)),
    );
  }

  /// 화면을 옮긴다 — 실제 라우터로 간다.
  Future<void> goTo(
    WidgetTester tester,
    ProviderContainer container,
    String location,
  ) async {
    container.read(routerProvider).go(location);
    await tester.pumpAndSettle();
  }

  testWidgets('운행 화면을 나가도 위치 송신이 계속된다', (tester) async {
    final container = await pumpApp(tester);

    await goTo(tester, container, AppRoutes.driveMode);
    await tester.pump(_interval);
    expect(repository.calls, hasLength(1));

    await goTo(tester, container, AppRoutes.home);
    await tester.pump(_interval);
    await tester.pump(_interval);

    expect(
      repository.calls,
      hasLength(3),
      reason: '운행 화면을 나간 뒤에도 2초마다 송신이 이어져야 한다',
    );
  });

  testWidgets('운행 화면을 한 번도 열지 않아도 운행 중인 기사 회차면 홈에서도 송신한다', (tester) async {
    await pumpApp(tester);

    await tester.pump(_interval);
    await tester.pump(_interval);

    expect(repository.calls, hasLength(2));
  });

  testWidgets('운행 화면을 다시 열어도 송신기는 하나다 — 주기마다 요청은 1건', (tester) async {
    final container = await pumpApp(tester);

    await goTo(tester, container, AppRoutes.driveMode);
    await goTo(tester, container, AppRoutes.home);
    await goTo(tester, container, AppRoutes.driveMode);
    final before = repository.calls.length;

    await tester.pump(_interval);
    await tester.pump(_interval);
    await tester.pump(_interval);

    expect(repository.calls.length - before, 3);
    expect(source.stopCalls, 0, reason: '화면을 오간다고 위치 스트림을 껐다 켜지 않는다');
  });

  testWidgets('로그아웃하면 송신이 멈춘다', (tester) async {
    await pumpApp(tester);
    await tester.pump(_interval);
    expect(repository.calls, hasLength(1));

    // 로그아웃은 내 정보 탭 맨 아래에만 있다(`Ruling 826`).
    await tester.tap(find.text('내 정보'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BaraedaDialog),
        matching: find.text('로그아웃'),
      ),
    );
    await tester.pumpAndSettle();
    final afterLogout = repository.calls.length;

    await tester.pump(_interval * 3);

    expect(repository.calls.length, afterLogout);
    expect(source.stopCalls, greaterThan(0));
  });

  testWidgets('마지막 도착 처리 응답이 오면 회차가 아직 moving 이어도 송신이 멈춘다', (tester) async {
    final container = await pumpApp(tester);
    await goTo(tester, container, AppRoutes.driveMode);
    await tester.pump(_interval);
    expect(repository.calls, hasLength(1));

    await tester.tap(find.text('도착 처리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('도착했어요 · 운행 종료'));
    await tester.pumpAndSettle();
    final afterArrive = repository.calls.length;

    await tester.pump(_interval * 3);

    expect(repository.calls.length, afterArrive);
  });

  // F06-12 — 송신 대상은 "내가 기사이고 운행 중인 회차" 이지 화면에서 고른 회차가 아니다. 운행 중 홈에서
  // 다른 회차 카드를 눌러도 학부모 지도의 버스가 멈추면 안 된다.
  testWidgets('운행 중 홈에서 다른 회차를 골라도 송신은 운행 중인 회차로 이어진다', (tester) async {
    final container = await pumpApp(
      tester,
      runs: [
        managerRunFixture(status: RunStatus.moving, roleInRun: UserRole.driver),
        managerRunFixture(runId: 'run-2'),
      ],
    );
    await tester.pump(_interval);
    expect(repository.calls, hasLength(1));

    container.read(selectedRunIdProvider.notifier).state = 'run-2';
    await tester.pump(_interval);
    await tester.pump(_interval);

    expect(repository.calls, hasLength(3), reason: '다른 회차를 골라도 2초마다 이어져야 한다');
    expect(source.stopCalls, 0);
  });

  // K-02② (F06-07 (3)) — 음영 구간에서 앞 요청이 끝나지 않았는데 2초마다 새 요청을 열면 수십 개가 쌓였다가
  // 복구 순간 한꺼번에 도착한다. 앞 송신이 진행 중이면 그 주기는 건너뛴다.
  testWidgets('앞 위치 요청이 끝나지 않았으면 다음 주기는 새 요청을 열지 않는다', (tester) async {
    await pumpApp(tester);
    repository.hang = true;

    await tester.pump(_interval);
    await tester.pump(_interval);
    await tester.pump(_interval);
    await tester.pump(_interval);

    expect(repository.calls, hasLength(1));
  });

  testWidgets('전송이 성공하면 마지막 성공 시각을 기록하고, 실패하면 그 시각을 그대로 둔다 (R46)', (
    tester,
  ) async {
    final container = await pumpApp(tester);
    expect(container.read(positionLinkProvider).startedAt, isNotNull);
    expect(container.read(positionLinkProvider).lastSentAt, isNull);

    await tester.pump(_interval);
    final sentAt = container.read(positionLinkProvider).lastSentAt;
    expect(sentAt, isNotNull, reason: '서버가 받았으면 시각이 남는다');

    repository.failWith = const NetworkFailure();
    await tester.pump(_interval);
    await tester.pump(_interval);

    expect(repository.calls.length, greaterThan(1));
    expect(
      container.read(positionLinkProvider).lastSentAt,
      sentAt,
      reason: '실패한 전송은 마지막 성공 시각을 바꾸지 않는다',
    );
  });

  // F06-17 — 좌표가 그대로면 상태가 같은 값이라 화면을 다시 그리게 알리지 않는다.
  testWidgets('같은 좌표가 이어지면 구독자에게 다시 알리지 않는다', (tester) async {
    final container = await pumpApp(tester);
    var notifications = 0;
    container.listen(positionTransmitterProvider, (_, _) => notifications++);

    await tester.pump(_interval);
    await tester.pump(_interval);
    await tester.pump(_interval);
    await tester.pump(_interval);

    expect(notifications, 1, reason: '처음 값이 채워질 때 한 번뿐이어야 한다');
  });

  testWidgets('권한이 없어 못 보내는 동안에는 주기마다 소스에 다시 확인시킨다(F06-03)', (tester) async {
    await pumpApp(tester, unavailable: true);
    final startsAtBegin = source.startCalls;

    await tester.pump(_interval * 2);

    expect(source.startCalls, greaterThan(startsAtBegin));
  });

  // F06-16 — 마지막 도착 처리 요청 중에 화면이 닫혀도 서버는 이미 운행을 끝냈다. 종료 처리(위치 송신 중단)가
  // 화면 생존에 기대면 송신이 계속되고, 닫힌 화면의 ref 를 써서 처리되지 않은 예외도 남는다.
  testWidgets('마지막 도착 처리 응답 전에 화면이 닫혀도 위치 송신은 멈추고 예외가 남지 않는다', (tester) async {
    final container = await pumpApp(tester);
    await goTo(tester, container, AppRoutes.driveMode);
    arriveRepository.gate = Completer<void>();

    await tester.tap(find.text('도착 처리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('도착했어요 · 운행 종료'));
    await tester.pump();
    await goTo(tester, container, AppRoutes.home);

    arriveRepository.gate!.complete();
    await tester.pumpAndSettle();
    final afterArrive = repository.calls.length;
    await tester.pump(_interval * 3);

    expect(tester.takeException(), isNull);
    expect(repository.calls.length, afterArrive, reason: '종점 도착 뒤에는 송신이 멈춘다');
  });

  testWidgets('동승자는 운행 중이어도 어느 화면에서든 보내지 않는다', (tester) async {
    await pumpApp(tester, role: UserRole.escort);

    await tester.pump(_interval * 3);

    expect(repository.calls, isEmpty);
    expect(source.startCalls, 0);
  });

  testWidgets('운행 중이 아닌 회차는 보내지 않는다', (tester) async {
    await pumpApp(tester, status: RunStatus.confirmed);

    await tester.pump(_interval * 3);

    expect(repository.calls, isEmpty);
  });
}
