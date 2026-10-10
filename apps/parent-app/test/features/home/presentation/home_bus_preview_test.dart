import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/academy_contact.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/role_policy.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/change_requests/presentation/change_request_providers.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/core/map/map_surface.dart';
import 'package:parent_app/core/routes/domain/route_detail.dart';
import 'package:parent_app/core/routes/domain/route_repository.dart';
import 'package:parent_app/core/runs/domain/bus_position.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';
import 'package:parent_app/features/home/presentation/widgets/home_bus_preview.dart';
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

/// 노선(§3.10)을 읽는 요청의 `run_id` 를 남기는 가짜 — 값이 없으면 실패한다.
class _RecordingRouteRepository implements RouteRepository {
  new(this._detail);

  final RouteDetail? _detail;
  final List<String?> runIds = [];

  @override
  Future<RouteDetail> getRoute(
    String studentId, {
    DateTime? date,
    String? runId,
  }) {
    runIds.add(runId);
    final detail = _detail;
    return detail == null
        ? Future.error(const Failure.unknown(message: 'test fake — no route'))
        : Future.value(detail);
  }
}

final List<({double lat, double lng})> _road = [
  (lat: 37.501, lng: 126.701),
  (lat: 37.502, lng: 126.703),
  (lat: 37.504, lng: 126.704),
];

/// 표시 범위만 담은 노선 — 3 · 4(내 승하차지) · 5 번.
RouteDetail _route({
  List<({double lat, double lng})>? roadPath,
  bool arrived = false,
}) => RouteDetail(
  runId: 'run-1',
  busNo: '2호차',
  departTime: DateTime.utc(2026, 10, 3, 3, 20),
  confirmed: true,
  driver: const RouteDriver(name: null),
  escort: const RouteEscort(name: null, phone: null),
  myStopId: 'st-1',
  roadPath: roadPath ?? _road,
  stops: [
    RouteStop(
      stopId: 'st-3',
      seq: 3,
      name: '중앙공원 앞',
      address: null,
      lat: 37.501,
      lng: 126.701,
      arrivedAt: arrived ? DateTime.utc(2026, 10, 3, 3, 9) : null,
    ),
    RouteStop(
      stopId: 'st-1',
      seq: 4,
      name: '행복마을 입구',
      address: null,
      lat: 37.502,
      lng: 126.703,
      arrivedAt: arrived ? DateTime.utc(2026, 10, 3, 3, 15) : null,
    ),
    const RouteStop(
      stopId: 'st-5',
      seq: 5,
      name: '하늘수학',
      address: null,
      lat: 37.504,
      lng: 126.704,
    ),
  ],
);

BusPosition _position({
  BusDelay? delay,
  DateTime? receivedAt,
  String? stopName = '중앙공원 앞',
  DateTime? stopArrivedAt,
  RunStatus status = RunStatus.moving,
  bool withCoords = true,
}) => BusPosition(
  runId: 'run-1',
  busNo: '2호차',
  runStatus: status,
  lat: withCoords ? 37.5 : null,
  lng: withCoords ? 126.7 : null,
  receivedAt: receivedAt,
  currentStopName: stopName,
  currentStopArrivedAt: stopArrivedAt,
  delay: delay,
);

StudentRun _run({RiderStatus riderStatus = RiderStatus.waiting}) => StudentRun(
  runId: 'run-1',
  direction: RunDirection.toAcademy,
  busNo: '2호차',
  departTime: DateTime.utc(2026, 10, 3, 3, 20),
  runStatus: RunStatus.moving,
  confirmed: true,
  riding: true,
  riderStatus: riderStatus,
  stop: const RunStop(stopId: 'st-1', name: '행복마을 입구'),
  changeQuotaLeft: 1,
);

Future<_CountingPositionRepository> _pumpHome(
  WidgetTester tester, {
  required Future<BusPosition> Function() position,
  UserRole role = UserRole.parent,
  RouteDetail? route,
  _RecordingRouteRepository? routeRepository,
  RiderStatus riderStatus = RiderStatus.waiting,
  DateTime? now,
  String? savedContact,
  ChangeRequestPage? changeRequests,
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
        routeRepositoryProvider.overrideWithValue(
          routeRepository ?? _RecordingRouteRepository(route),
        ),
        if (now != null) clockProvider.overrideWithValue(_FixedClock(now)),
        savedAcademyContactProvider.overrideWith((ref) async => savedContact),
        currentUserRoleProvider.overrideWith((ref) => role),
        roleCapabilitiesProvider.overrideWithValue(RoleCapabilities.of(role)),
        myStudentsProvider.overrideWith(
          (ref) async => [
            Student(studentId: 's-1', name: '이하준', linkedAt: DateTime(2026, 9)),
          ],
        ),
        myStudentIdProvider.overrideWith((ref) async => 's-1'),
        runsForStudentProvider.overrideWith(
          (ref, id) async => [_run(riderStatus: riderStatus)],
        ),
        changeRequestsProvider.overrideWith(
          (ref, id) async =>
              changeRequests ??
              const ChangeRequestPage(items: [], pendingCount: 0),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

/// 미리보기 카드 안의 글자만 찾는다 — 아래 회차 카드(`RunCard`)도 같은 칩 글자를 쓴다.
Finder _inPreview(String text) =>
    find.descendant(of: find.byType(HomeBusPreview), matching: find.text(text));

class _FixedClock implements Clock {
  const new(this._value);

  final DateTime _value;

  @override
  DateTime now() => _value;
}

void main() {
  // R52 M2 — 칩은 전체 지도(`LiveMapView.resolve`)와 같은 판정을 따른다.
  group('R52 M2 칩 — 신호 유실 · 미등원', () {
    final now = DateTime.utc(2026, 10, 3, 3, 30);

    testWidgets('좌표 없이 last_seen_at 만 오고 2분이 넘었으면 "신호 없음" 이다 — "이동 중" 이 아니다', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        now: now,
        position: () async => BusPosition(
          runId: 'run-1',
          busNo: '2호차',
          runStatus: RunStatus.moving,
          lastSeenAt: now.subtract(const Duration(minutes: 5)),
        ),
      );

      expect(_inPreview('신호 없음'), findsOneWidget);
      expect(_inPreview('이동 중'), findsNothing);
    });

    testWidgets('받은 좌표가 2분을 넘겨 묵었으면 "신호 없음" 이다', (tester) async {
      await _pumpHome(
        tester,
        now: now,
        position: () async =>
            _position(receivedAt: now.subtract(const Duration(minutes: 3))),
      );

      expect(_inPreview('신호 없음'), findsOneWidget);
      expect(_inPreview('이동 중'), findsNothing);
    });

    testWidgets('2분 안에 받은 좌표면 "이동 중" 이다', (tester) async {
      await _pumpHome(
        tester,
        now: now,
        position: () async =>
            _position(receivedAt: now.subtract(const Duration(minutes: 1))),
      );

      expect(_inPreview('이동 중'), findsOneWidget);
      expect(_inPreview('신호 없음'), findsNothing);
    });

    // 유실 경계(Ruling 208 · 2분) — 2분 직전은 이동 중, 2분 직후는 신호 없음. 임계값을 바꾸면 여기서 깨진다.
    testWidgets('마지막 좌표가 2분 직전(1분 59초)이면 유실이 아니라 "이동 중" 이다', (tester) async {
      await _pumpHome(
        tester,
        now: now,
        position: () async => _position(
          receivedAt: now.subtract(const Duration(minutes: 1, seconds: 59)),
        ),
      );

      expect(_inPreview('이동 중'), findsOneWidget);
      expect(_inPreview('신호 없음'), findsNothing);
    });

    testWidgets('마지막 좌표가 2분 직후(2분 1초)면 유실로 "신호 없음" 이다', (tester) async {
      await _pumpHome(
        tester,
        now: now,
        position: () async => _position(
          receivedAt: now.subtract(const Duration(minutes: 2, seconds: 1)),
        ),
      );

      expect(_inPreview('신호 없음'), findsOneWidget);
      expect(_inPreview('이동 중'), findsNothing);
    });

    testWidgets('오늘 미등원이면 칩이 "미등원" 이다 — "이동 중" 이 아니다', (tester) async {
      await _pumpHome(
        tester,
        now: now,
        riderStatus: RiderStatus.absent,
        position: () async => _position(),
      );

      expect(_inPreview('미등원'), findsOneWidget);
      expect(_inPreview('이동 중'), findsNothing);
    });
  });

  // R52 낮음 A11 — 버스 위치를 못 불러온 화면에도 급할 때 걸 학원 전화가 있다(홈 전체 실패 화면과 같은 카드).
  group('A11 버스 위치 실패 화면의 학원 전화', () {
    Future<void> failToLoad(WidgetTester tester, {String? savedContact}) =>
        _pumpHome(
          tester,
          savedContact: savedContact,
          position: () =>
              Future.error(const Failure.network(message: '연결할 수 없습니다')),
        );

    testWidgets('기기에 남긴 문의처에 번호가 있으면 오류 띠 아래에 학원 전화 카드가 나온다', (tester) async {
      await failToLoad(tester, savedContact: '학원 데스크 032-000-1100');

      expect(find.text('버스 위치를 불러오지 못했어요'), findsOneWidget);
      expect(find.text('버스가 급하게 궁금하면'), findsOneWidget);
      expect(find.text('학원 032-000-1100'), findsOneWidget);
    });

    testWidgets('번호가 없으면 오류 띠만 있고 전화 카드는 없다', (tester) async {
      await failToLoad(tester, savedContact: '학원에 직접 문의');

      expect(find.text('버스 위치를 불러오지 못했어요'), findsOneWidget);
      expect(find.text('버스가 급하게 궁금하면'), findsNothing);
    });
  });

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
            reason: 'traffic',
            sentAt: DateTime.utc(2026, 10, 3, 3, 12),
          ),
        ),
      );

      expect(find.text('버스가 10분 늦어요'), findsOneWidget);
      expect(find.text('교통 체증'), findsOneWidget);
      // 서버 코드(traffic)는 글자로 나오지 않는다.
      expect(find.text('traffic'), findsNothing);
    });

    testWidgets('모르는 사유는 코드를 띄우지 않고 사유 줄만 숨긴다', (tester) async {
      await _pumpHome(
        tester,
        position: () async => _position(
          delay: BusDelay(
            minutes: 10,
            reason: 'flat_tire',
            sentAt: DateTime.utc(2026, 10, 3, 3, 12),
          ),
        ),
      );

      expect(find.text('버스가 10분 늦어요'), findsOneWidget);
      expect(find.text('flat_tire'), findsNothing);
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

  testWidgets('오늘 회차가 없으면(404 RUN_NOT_FOUND) 미리보기 카드를 그리지 않는다', (tester) async {
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
    // 같은 안내를 두 번 쓰지 않는다 — 회차 목록 쪽 문구가 이미 있다(시뮬레이터에서 겹쳐 보였던 결함).
    expect(find.text('오늘은 운행이 없어요'), findsNothing);
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

  // R52 870 — 같은 회차 대기 신청이 여럿이면 가장 이른 마감을 카드에 보인다.
  group('승인 대기 마감 — 여러 신청 중 가장 이른 마감(Ruling 870)', () {
    final now = DateTime.utc(2026, 10, 3, 3, 30);
    ChangeRequest pending(String id, DateTime deadline) => ChangeRequest(
      changeRequestId: id,
      type: ChangeRequestType.cancel,
      status: ChangeRequestStatus.pending,
      runId: 'run-1',
      deadlineAt: deadline,
    );

    testWidgets('대기 신청이 2건이면 더 이른 마감(5분 뒤)을 쓴다 — 늦은 마감(40분)은 쓰지 않는다', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        now: now,
        position: () async => _position(),
        changeRequests: ChangeRequestPage(
          items: [
            pending('c-late', now.add(const Duration(minutes: 40))),
            pending('c-early', now.add(const Duration(minutes: 5))),
          ],
          pendingCount: 2,
        ),
      );

      expect(find.text('승인 대기 · 마감까지 5분'), findsOneWidget);
      expect(find.text('승인 대기 · 마감까지 40분'), findsNothing);
    });

    testWidgets('마감이 이미 지났으면 "승인 대기" 만 보이고 남은 시간은 없다', (tester) async {
      await _pumpHome(
        tester,
        now: now,
        position: () async => _position(),
        changeRequests: ChangeRequestPage(
          items: [pending('c-old', now.subtract(const Duration(minutes: 1)))],
          pendingCount: 1,
        ),
      );

      expect(find.text('승인 대기'), findsOneWidget);
      expect(find.textContaining('마감까지'), findsNothing);
    });
  });

  // R49 `Ruling 831` — 홈 지도 미리보기에도 표시 범위 승하차지의 번호 마커와 경로선을 그린다.
  group('R49 지도 미리보기 — 노선선 · 번호', () {
    MapSurface previewMap(WidgetTester tester) =>
        tester.widget<MapSurface>(find.byType(MapSurface));

    testWidgets('road_path 가 있으면 선 1개와 번호 마커(번호는 seq)를 그리고 내 승하차지를 강조한다', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        position: () async => _position(),
        route: _route(),
      );

      final map = previewMap(tester);
      final stops = map.markers.where((m) => m.kind == MapMarkerKind.stop);
      expect(map.polylines, hasLength(1));
      expect(map.polylines.single.dashed, isFalse);
      expect(stops.map((m) => m.seq), [3, 4, 5]);
      expect(map.markers.where((m) => m.mine).map((m) => m.seq), [4]);
      expect(
        map.markers.where((m) => m.kind == MapMarkerKind.bus),
        hasLength(1),
      );
    });

    testWidgets('road_path 가 비면 표시 승하차지를 점선으로 잇는다', (tester) async {
      await _pumpHome(
        tester,
        position: () async => _position(),
        route: _route(roadPath: const []),
      );

      final line = previewMap(tester).polylines.single;
      expect(line.dashed, isTrue);
      expect(line.points, hasLength(3));
    });

    testWidgets('노선을 못 받으면 버스만 그리고 오류 띠를 더하지 않는다', (tester) async {
      await _pumpHome(tester, position: () async => _position());

      final map = previewMap(tester);
      expect(map.polylines, isEmpty);
      expect(map.markers.map((m) => m.kind), [MapMarkerKind.bus]);
      expect(find.byType(AlertBanner), findsNothing);
    });

    testWidgets('노선 요청에 스냅샷의 run_id 를 싣는다', (tester) async {
      final routes = _RecordingRouteRepository(_route());
      await _pumpHome(
        tester,
        position: () async => _position(),
        routeRepository: routes,
      );

      expect(routes.runIds, isNotEmpty);
      expect(routes.runIds.toSet(), {'run-1'});
    });

    testWidgets('종료된 회차는 좌표가 없어도 지나온 구간을 그리고 지도를 노선에 맞춘다', (tester) async {
      await _pumpHome(
        tester,
        position: () async =>
            _position(status: RunStatus.finished, withCoords: false),
        route: _route(arrived: true),
      );

      final map = previewMap(tester);
      expect(map.polylines.single.passed, isTrue);
      expect(map.markers.where((m) => m.kind == MapMarkerKind.bus), isEmpty);
      expect(map.markers.map((m) => m.seq), [3, 4, 5]);
      expect(map.fitToContent, isTrue);
    });

    // 2026-10-07 사용자 지시(Ruling 842) — 출발 전 카드가 빈 면이라 "지도가 안 보인다" 로 읽혔다.
    testWidgets('운행 전 회차는 버스 없이 노선(경로선 · 번호)을 미리 그리고 지도를 노선에 맞춘다', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        position: () async =>
            _position(status: RunStatus.confirmed, withCoords: false),
        route: _route(),
      );

      final map = previewMap(tester);
      expect(map.polylines.single.passed, isFalse);
      expect(map.markers.where((m) => m.kind == MapMarkerKind.bus), isEmpty);
      expect(map.markers.map((m) => m.seq), [3, 4, 5]);
      expect(map.markers.where((m) => m.mine).map((m) => m.seq), [4]);
      expect(map.fitToContent, isTrue);
    });

    testWidgets('운행 전인데 노선도 못 받으면 지도를 그리지 않는다 — 근거 없는 카메라 위치를 잡지 않는다', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        position: () async =>
            _position(status: RunStatus.confirmed, withCoords: false),
      );

      expect(find.byType(MapSurface), findsNothing);
    });
  });
}
