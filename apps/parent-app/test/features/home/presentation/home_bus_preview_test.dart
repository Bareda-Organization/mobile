import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/role_policy.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/change_requests/presentation/change_request_providers.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/core/runs/domain/bus_position.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';
import 'package:parent_app/features/live_map/domain/bus_position_repository.dart';

/// R48 홈 지도 미리보기(`Ruling 821`) — **WebSocket 을 구독하지 않고** §3.11 을 30초마다 다시 읽는다.
/// 구독은 전체 지도 화면에서만 한다(WebSocket 팬아웃은 부하 여유가 가장 얇은 갈래).

/// 어떤 메서드든 부르면 시험이 죽는 WebSocket 대역 — 홈이 이것을 건드리면 그 자리에서 실패한다.
class _ForbiddenWsClient implements BaraedaWebSocketClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('홈 지도 미리보기가 WebSocket 을 건드렸다: ${invocation.memberName}');
}

class _CountingPositionRepository implements BusPositionRepository {
  new(this._response);

  final Future<BusPosition> Function() _response;
  int calls = 0;
  final List<String> studentIds = [];

  @override
  Future<BusPosition> getBusPosition(String studentId) {
    calls++;
    studentIds.add(studentId);
    return _response();
  }
}

BusPosition _position({
  BusDelay? delay,
  DateTime? receivedAt,
  String? stopName = '중앙공원 앞',
  DateTime? stopArrivedAt,
}) => BusPosition(
  runId: 'run-1',
  busNo: '2호차',
  runStatus: RunStatus.moving,
  lat: 37.5,
  lng: 126.7,
  receivedAt: receivedAt,
  currentStopName: stopName,
  currentStopArrivedAt: stopArrivedAt,
  delay: delay,
);

StudentRun _run() => StudentRun(
  runId: 'run-1',
  direction: RunDirection.toAcademy,
  busNo: '2호차',
  departTime: DateTime.utc(2026, 10, 3, 3, 20),
  runStatus: RunStatus.moving,
  confirmed: true,
  riding: true,
  riderStatus: RiderStatus.waiting,
  stop: const RunStop(stopId: 'st-1', name: '행복마을 입구'),
  changeQuotaLeft: 1,
);

Future<_CountingPositionRepository> _pumpHome(
  WidgetTester tester, {
  required Future<BusPosition> Function() position,
  UserRole role = UserRole.parent,
}) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = _CountingPositionRepository(position);
  final router = GoRouter(
    // 홈이 서 있는 경로가 `/home` 이어야 "다른 화면에 가려지지 않음" 으로 읽혀 주기 갱신이 돈다.
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(path: AppRoutes.home, builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: AppRoutes.liveMap,
        builder: (_, _) => const Scaffold(body: Text('전체 지도')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        webSocketClientProvider.overrideWithValue(_ForbiddenWsClient()),
        busPositionRepositoryProvider.overrideWithValue(repository),
        currentUserRoleProvider.overrideWith((ref) => role),
        roleCapabilitiesProvider.overrideWithValue(RoleCapabilities.of(role)),
        myStudentsProvider.overrideWith(
          (ref) async => [
            Student(studentId: 's-1', name: '이하준', linkedAt: DateTime(2026, 9)),
          ],
        ),
        myStudentIdProvider.overrideWith((ref) async => 's-1'),
        runsForStudentProvider.overrideWith((ref, id) async => [_run()]),
        changeRequestsProvider.overrideWith(
          (ref, id) async =>
              const ChangeRequestPage(items: [], pendingCount: 0),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('지도 미리보기는 WebSocket 을 구독하지 않는다 — 건드리면 이 시험이 죽는다', (tester) async {
    await _pumpHome(tester, position: () async => _position());

    expect(find.text('2호차'), findsWidgets);
    // 위 _ForbiddenWsClient 가 아무 호출도 받지 않았다(받았다면 StateError 로 이미 실패).
    expect(tester.takeException(), isNull);
  });

  testWidgets('§3.11 을 처음 한 번 읽고, 30초가 지나면 다시 읽는다 — 29초에는 안 읽는다', (
    tester,
  ) async {
    final repository = await _pumpHome(
      tester,
      position: () async => _position(),
    );
    expect(repository.calls, 1);
    expect(repository.studentIds, ['s-1']);

    await tester.pump(const Duration(seconds: 29));
    expect(repository.calls, 1, reason: '30초 전에는 다시 읽지 않는다');

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);

    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(repository.calls, 3);
  });

  group('지연 띠(§3.11 delay)', () {
    testWidgets('delay 가 있으면 "버스가 10분 늦어요 · 교통 체증" 띠가 나온다', (tester) async {
      await _pumpHome(
        tester,
        position: () async => _position(
          delay: BusDelay(
            minutes: 10,
            reason: '교통 체증',
            sentAt: DateTime.utc(2026, 10, 3, 3, 12),
          ),
        ),
      );

      expect(find.text('버스가 10분 늦어요'), findsOneWidget);
      expect(find.text('교통 체증'), findsOneWidget);
    });

    testWidgets('사유가 없는 지연은 띠만 나온다', (tester) async {
      await _pumpHome(
        tester,
        position: () async => _position(
          delay: BusDelay(minutes: 5, sentAt: DateTime.utc(2026, 10, 3, 3, 12)),
        ),
      );

      expect(find.text('버스가 5분 늦어요'), findsOneWidget);
    });

    testWidgets('delay 가 null 이면 띠가 없다 — 지연을 짐작해 그리지 않는다', (tester) async {
      await _pumpHome(tester, position: () async => _position());

      expect(find.textContaining('늦어요'), findsNothing);
    });
  });

  testWidgets('마지막으로 지난 곳 · 시각과 내 승하차지가 한 칸에 나란히 있다', (tester) async {
    await _pumpHome(
      tester,
      position: () async => _position(
        stopArrivedAt: DateTime(2026, 10, 3, 12, 9),
        receivedAt: DateTime(2026, 10, 3, 12, 14),
      ),
    );

    expect(find.text('중앙공원 앞'), findsOneWidget);
    expect(find.text('마지막으로 지난 곳 · 12:09'), findsOneWidget);
    expect(find.text('행복마을 입구'), findsWidgets);
    expect(find.text('내 승하차지'), findsOneWidget);
    expect(find.text('12:14 기준'), findsOneWidget);
  });

  testWidgets('받은 위치가 없으면 "기준" 시각을 숨긴다 — 없는 값을 보이면 거짓 정보(P8)', (tester) async {
    await _pumpHome(tester, position: () async => _position());

    expect(find.textContaining('기준'), findsNothing);
  });

  testWidgets('시각이 없으면 "마지막으로 지난 곳" 은 이름만 붙는다', (tester) async {
    await _pumpHome(tester, position: () async => _position());

    expect(find.text('마지막으로 지난 곳'), findsOneWidget);
  });

  testWidgets('지도 단추를 누르면 전체 지도 화면으로 간다', (tester) async {
    await _pumpHome(tester, position: () async => _position());

    await tester.tap(find.bySemanticsLabel('전체 지도 열기'));
    await tester.pumpAndSettle();

    expect(find.text('전체 지도'), findsOneWidget);
  });

  testWidgets('오늘 회차가 없으면(404 RUN_NOT_FOUND) 미리보기 카드 대신 안내가 나온다', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      position: () => Future.error(
        const Failure.api(
          statusCode: 404,
          code: 'RUN_NOT_FOUND',
          message: '오늘 회차가 없습니다',
        ),
      ),
    );

    expect(find.text('2호차'), findsNothing);
    expect(find.byType(BaraedaMapButton), findsNothing);
    expect(find.text('오늘은 운행이 없어요'), findsOneWidget);
  });

  group('머리줄', () {
    testWidgets('학부모 홈 제목은 "우리 아이 버스" 이고 로그아웃 단추가 없다(Ruling 826)', (
      tester,
    ) async {
      await _pumpHome(tester, position: () async => _position());

      expect(find.text('우리 아이 버스'), findsOneWidget);
      expect(find.text('로그아웃'), findsNothing);
    });

    testWidgets('학생 홈 제목은 "내 버스" 이고 로그아웃 단추가 없다', (tester) async {
      await _pumpHome(
        tester,
        position: () async => _position(),
        role: UserRole.student,
      );

      expect(find.text('내 버스'), findsOneWidget);
      expect(find.text('로그아웃'), findsNothing);
    });
  });
}
