import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/role_policy.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/core/map/map_surface.dart';
import 'package:parent_app/core/routes/domain/route_detail.dart';
import 'package:parent_app/core/routes/domain/route_repository.dart';
import 'package:parent_app/core/runs/domain/bus_position.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/runs/presentation/run_display.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';
import 'package:parent_app/core/students/presentation/student_switcher.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/live_map/domain/bus_position_repository.dart';
import 'package:parent_app/features/live_map/presentation/live_map_providers.dart';
import 'package:parent_app/features/live_map/presentation/live_map_screen.dart';
import 'package:parent_app/features/live_map/presentation/widgets/live_map_sheet.dart';
// `Override` 는 `flutter_riverpod.dart` 배럴이 재노출하지 않는다(3.4.3 확인 —
// `ProviderScope.overrides` 내부에서만 쓰고 공개 `show` 목록엔 없음). 실제
// 정의는 `riverpod` 패키지의 `misc.dart` 가 공개한다 — `flutter_riverpod` 가
// 전이 의존성으로 이미 끌어오므로 `pubspec.yaml` 에 직접 추가할 필요는 없다.
import 'package:riverpod/misc.dart' show Override;

/// `webSocketClientProvider` 를 대신하는 가짜 — 실 STOMP 소켓을 열지 않고
/// `LiveMapNotifier` 가 실제로 쓰는 공개 API(`state`·`connectionState`·
/// `forbiddenSubscriptions`·`connect`·`subscribe`)만 흉내 낸다.
///
/// **판단 근거 — `LiveMapNotifier` 를 가짜로 바꿔치기하지 않고 클라이언트
/// 한 겹만 가짜로 둔 이유**: `StateNotifierProvider.family` 의 `overrideWith`
/// 는 정확히 `LiveMapNotifier` 타입을 요구해 다른 구현으로 바꿔치기하기
/// 어렵고(§ pending tasks 판단), 무엇보다 이 화면이 검증해야 할 것은
/// "연결 상태·이벤트가 실제 notifier 로직을 거쳐 화면에 반영되는가"라
/// notifier 자체를 가짜로 두면 그 로직이 시험 대상에서 빠진다.
class _FakeWsClient extends BaraedaWebSocketClient {
  new()
    : super(
        url: 'ws://test.invalid/ws/location',
        tokenStorage: TokenStorage(
          accessTokenKey: 'live-map-test-access',
          refreshTokenKey: 'live-map-test-refresh',
        ),
      );

  final _stateController = StreamController<WsConnectionState>.broadcast();
  final _forbiddenController = StreamController<String>.broadcast();
  WsConnectionState _fakeState = WsConnectionState.disconnected;
  final List<void Function(WebSocketEnvelope)> _listeners = [];
  final List<String> subscribedDestinations = [];

  /// `subscribe`·해지 콜백 호출을 시각 순서대로 남긴다 — "자녀를 전환할
  /// 때 해지가 구독보다 먼저인가"(팀 리드 우려 3)는 최종 상태만 보면
  /// 안 갈리고 순서를 봐야 갈린다.
  final List<String> callLog = [];

  @override
  WsConnectionState get state => _fakeState;

  @override
  Stream<WsConnectionState> get connectionState => _stateController.stream;

  @override
  Stream<String> get forbiddenSubscriptions => _forbiddenController.stream;

  /// `connect()` 가 불린 횟수 — [다시 시도] 가 실제로 재연결을 거는지 본다.
  int connectCalls = 0;

  @override
  void connect() {
    // 실 소켓을 열지 않는다 — 시험은 [emit] 으로 상태 전이를 직접 민다.
    connectCalls++;
  }

  /// 실 서버 대신 연결 상태 전이를 흘려보낸다.
  void emit(WsConnectionState next) {
    _fakeState = next;
    _stateController.add(next);
  }

  void forbid(String destination) => _forbiddenController.add(destination);

  @override
  void Function({Map<String, String>? unsubscribeHeaders}) subscribe(
    String destination,
    void Function(WebSocketEnvelope) onEnvelope,
  ) {
    subscribedDestinations.add(destination);
    callLog.add('subscribe:$destination');
    _listeners.add(onEnvelope);
    return ({Map<String, String>? unsubscribeHeaders}) {
      subscribedDestinations.remove(destination);
      callLog.add('unsubscribe:$destination');
      _listeners.remove(onEnvelope);
    };
  }

  /// 그 봉투의 목적지에 걸린 구독자 전원에게 배달한다 — 실 서버의
  /// 방송(broadcast)과 같은 모양이다.
  void deliver(WebSocketEnvelope envelope) {
    for (final listener in List.of(_listeners)) {
      listener(envelope);
    }
  }

  @override
  void dispose() {
    // 실 구현의 dispose() 는 disconnect()(내부 _stompClient.deactivate())를
    // 부르는데 이 가짜는 소켓을 연 적이 없다 — 스트림 컨트롤러만 닫는다.
    unawaited(_stateController.close());
    unawaited(_forbiddenController.close());
  }
}

/// `busPositionRepositoryProvider` 기본 가짜 — §3.11 스냅샷은 이 화면
/// 파일의 관심사가 아니므로(REST 흐름은 별도 시험으로 다룬다), 항상
/// 즉시 실패하게 해 둔다. 실 `ApiClient`(Dio)를 거치면 내부 타이머가
/// `FakeAsync` 위젯 트리 해제 뒤까지 남아 "A Timer is still pending"
/// 으로 전 시험이 깨진다 — `Future.error` 로 네트워크를 건드리지 않는
/// 것이 핵심이다. 이 파일의 기존 단언들은 `restPosition` 이 `null`
/// 이거나 에러인 것을 전제로 짜여 있어(REST 대체 렌더 분기의 가드
/// 조건이 전부 거짓이 되는 경로), 성공 응답을 흉내 낼 필요가 없다.
class _FakeBusPositionRepository implements BusPositionRepository {
  @override
  Future<BusPosition> getBusPosition(String studentId) =>
      Future.error(const Failure.unknown(message: 'test fake — no REST'));
}

/// 호출할 때마다 정해 둔 결과를 차례로 돌려주는 가짜 — 마지막 값은 이후에도 계속 쓴다.
/// 첫 진입 스냅샷과 재연결 뒤 스냅샷이 다른 값을 주는 시험에 쓴다.
class _ScriptedBusPositionRepository implements BusPositionRepository {
  new(this._results);

  final List<BusPosition> _results;
  int calls = 0;

  @override
  Future<BusPosition> getBusPosition(String studentId) async {
    final index = calls < _results.length ? calls : _results.length - 1;
    calls++;
    return _results[index];
  }
}

/// 응답이 끝내 오지 않는 가짜 — 첫 스냅샷을 기다리는 "불러오는 중" 화면을 붙잡아 둔다.
class _NeverBusPositionRepository implements BusPositionRepository {
  @override
  Future<BusPosition> getBusPosition(String studentId) =>
      Completer<BusPosition>().future;
}

/// 기본 노선 가짜 — 지도 시험 대부분은 내 승하차지 핀과 무관하므로 항상 실패하게 둔다.
/// 실 `ApiClient`(Dio)를 거치면 "A Timer is still pending" 으로 시험이 깨진다.
class _FakeRouteRepository implements RouteRepository {
  new([this.detail]);

  final RouteDetail? detail;

  /// 지금까지 노선을 요청한 `run_id` — R49: 종료된 회차도 그 회차의 노선을 읽는지 본다.
  static final List<String?> requestedRunIds = [];

  @override
  Future<RouteDetail> getRoute(
    String studentId, {
    DateTime? date,
    String? runId,
  }) {
    requestedRunIds.add(runId);
    return detail == null
        ? Future.error(const Failure.unknown(message: 'test fake — no route'))
        : Future.value(detail);
  }
}

RouteDetail _routeWithMyStop({double? lat = 37.51, double? lng = 127.02}) =>
    RouteDetail(
      runId: 'r-1',
      busNo: '1호차',
      departTime: DateTime.utc(2026, 9, 13, 8),
      confirmed: true,
      driver: const RouteDriver(name: null),
      escort: const RouteEscort(name: null, phone: null),
      myStopId: 'stop-mine',
      stops: [
        const RouteStop(
          stopId: 'stop-before',
          seq: 1,
          name: '앞 승하차지',
          address: null,
          lat: 37.5,
          lng: 127,
        ),
        RouteStop(
          stopId: 'stop-mine',
          seq: 2,
          name: '행복아파트 정문',
          address: null,
          lat: lat,
          lng: lng,
        ),
      ],
    );

WebSocketEnvelope _envelope(WsEventType event, Map<String, dynamic> payload) {
  return WebSocketEnvelope(
    event: event,
    eventWireValue: event.wireValue,
    runId: 'r-1',
    occurredAt: DateTime(2026, 9, 13, 8),
    payload: payload,
  );
}

/// P1(Ruling 208) — `clockProvider` 로 주입하는 가짜 시계. `home_screen_test.dart`
/// 의 `_FixedClock` 과 달리 한 시험 안에서 시각을 옮겨(`clock.value = ...`) 2분
/// 경과 전후를 비교해야 해서 값을 바꿀 수 있게 둔다.
class _MutableClock implements Clock {
  new(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

final _linkedAt = DateTime(2026);

/// R48 시안 `live-map--offline` 의 연결 끊김 띠 제목 — 옛 `_gaveUpTitle` 을 대신한다.
const _gaveUpTitle = '실시간 위치 연결이 끊어졌어요';

void main() {
  late _FakeWsClient client;

  setUp(() {
    client = _FakeWsClient();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<Override> extraOverrides,
    RouteDetail? route,
    BusPositionRepository? busPositionRepository,
    String? academyName,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          academyNameProvider.overrideWith((ref) async => academyName),
          webSocketClientProvider.overrideWithValue(client),
          busPositionRepositoryProvider.overrideWithValue(
            busPositionRepository ?? _FakeBusPositionRepository(),
          ),
          routeRepositoryProvider.overrideWithValue(
            _FakeRouteRepository(route),
          ),
          ...extraOverrides,
        ],
        child: const MaterialApp(home: LiveMapScreen()),
      ),
    );
  }

  group('학생 갈래', () {
    Future<void> pumpAsStudent(
      WidgetTester tester, {
      required String? studentId,
    }) => pumpScreen(
      tester,
      extraOverrides: [
        roleCapabilitiesProvider.overrideWithValue(
          RoleCapabilities.of(UserRole.student),
        ),
        myStudentIdProvider.overrideWith((ref) async => studentId),
      ],
    );

    // R32 P6 — 노선 자세히 보기(S-04)가 학부모 화면에만 있어 학생은 노선 상세로 갈 길이 없었다.
    testWidgets('학생 지도 화면에도 [노선 자세히 보기] 가 있다', (tester) async {
      await pumpAsStudent(tester, studentId: 's-1');
      await tester.pump();
      await tester.pump();

      expect(find.text('노선 자세히 보기'), findsOneWidget);
    });

    testWidgets('본인 student_id 가 없으면 [노선 자세히 보기] 를 보여주지 않는다', (tester) async {
      await pumpAsStudent(tester, studentId: null);
      await tester.pumpAndSettle();

      expect(find.text('노선 자세히 보기'), findsNothing);
    });

    testWidgets('본인 student_id 가 없으면 안내만 뜬다', (tester) async {
      await pumpAsStudent(tester, studentId: null);
      await tester.pumpAndSettle();

      expect(find.text('학생 계정 정보가 없습니다'), findsOneWidget);
    });

    testWidgets(
      '연결 직후(connecting)에는 로딩만 뜨고 "연결 끊김"·"데이터 없음" 문구는 뜨지 않는다',
      (tester) async {
        await pumpAsStudent(tester, studentId: 's-1');
        await tester.pump();

        expect(find.byType(MapSheetSkeleton), findsOneWidget);
        expect(find.text(_gaveUpTitle), findsNothing);
        expect(find.text('아직 위치 정보가 없습니다'), findsNothing);
      },
    );
  });

  group('학부모 갈래', () {
    Future<void> pumpAsParent(
      WidgetTester tester, {
      required List<Student> students,
    }) => pumpScreen(
      tester,
      extraOverrides: [
        roleCapabilitiesProvider.overrideWithValue(
          RoleCapabilities.of(UserRole.parent),
        ),
        myStudentsProvider.overrideWith((ref) async => students),
      ],
    );

    testWidgets('연결된 자녀가 없으면 연결 유도 카드가 뜬다', (tester) async {
      await pumpAsParent(tester, students: const []);
      await tester.pumpAndSettle();

      expect(find.text('연결된 자녀가 없습니다'), findsOneWidget);
      expect(find.text('자녀 연결하기'), findsOneWidget);
    });

    testWidgets('자녀가 1명이면 선택 UI 가 뜨지 않는다', (tester) async {
      await pumpAsParent(
        tester,
        students: [Student(studentId: 's-1', name: '홍길동', linkedAt: _linkedAt)],
      );
      await tester.pump();

      expect(find.byType(StudentSwitcher), findsOneWidget);
      expect(find.byType(BaraedaFilterPill), findsNothing);
    });

    testWidgets('자녀가 2명 이상이면 선택 UI 가 뜬다', (tester) async {
      await pumpAsParent(
        tester,
        students: [
          Student(studentId: 's-1', name: '홍길동', linkedAt: _linkedAt),
          Student(studentId: 's-2', name: '김철수', linkedAt: _linkedAt),
        ],
      );
      await tester.pump();

      expect(find.byType(BaraedaFilterPill), findsNWidgets(2));
    });
  });

  group('학부모 갈래 — 자녀 선택·전환과 구독(완료 조건 5)', () {
    Future<void> pumpConnectedParent(
      WidgetTester tester, {
      required List<Student> students,
    }) async {
      await pumpScreen(
        tester,
        extraOverrides: [
          roleCapabilitiesProvider.overrideWithValue(
            RoleCapabilities.of(UserRole.parent),
          ),
          myStudentsProvider.overrideWith((ref) async => students),
        ],
      );
      // myStudentsProvider 의 FutureProvider 가 해소될 때까지 한 프레임.
      await tester.pump();
      await tester.pump();
      client.emit(WsConnectionState.connected);
      await tester.pump();
    }

    final studentA = Student(studentId: 's-A', name: 'A', linkedAt: _linkedAt);
    final studentB = Student(studentId: 's-B', name: 'B', linkedAt: _linkedAt);

    testWidgets(
      '자녀를 아직 고르지 않아도(selectedStudentIdProvider == null) 첫 자녀 '
      '목적지로만 구독하고 null 목적지는 만들지 않는다(팀 리드 우려 2)',
      (tester) async {
        await pumpConnectedParent(tester, students: [studentA, studentB]);

        expect(client.subscribedDestinations, [WsChannel.studentRun('s-A')]);
        expect(
          client.subscribedDestinations.any((d) => d.contains('null')),
          isFalse,
        );
      },
    );

    testWidgets(
      '자녀를 전환하면 새 목적지 구독이 먼저 걸리고 이전 목적지 해지가 '
      '뒤따른다 — 팀 리드 우려 3 실측: `autoDispose` 는 위젯 재빌드가 새 '
      '목적지를 구독한 *뒤에* 더는 안 읽히는 이전 인스턴스를 해지하므로 '
      '한 프레임 동안 두 목적지가 겹친다. 이 겹침은 둘 다 같은 학부모 '
      '본인 자녀 목적지라 서버 인가상 안전하다(거부 대상이 아니다) — '
      '문제는 남의 자녀 목적지가 섞일 때인데 그 경로는 이 provider 가 '
      '애초에 만들지 않는다.',
      (tester) async {
        await pumpConnectedParent(tester, students: [studentA, studentB]);
        client.callLog.clear();

        // BaraedaSelect.onChanged 가 실제로 부르는 지점과 같은 provider
        // 갱신을 직접 호출한다 — 화면 트리거를 거치든 이 경로를 거치든
        // `_ParentLiveMap.build` 가 읽는 값은 같다.
        ProviderScope.containerOf(
          tester.element(find.byType(LiveMapScreen)),
          listen: false,
        ).read(selectedStudentIdProvider.notifier).state = 's-B';
        await tester.pump();

        final unsubA = client.callLog.indexOf(
          'unsubscribe:${WsChannel.studentRun('s-A')}',
        );
        final subB = client.callLog.indexOf(
          'subscribe:${WsChannel.studentRun('s-B')}',
        );

        expect(unsubA, greaterThanOrEqualTo(0));
        expect(subB, greaterThanOrEqualTo(0));
        expect(subB, lessThan(unsubA));
        expect(client.subscribedDestinations, [WsChannel.studentRun('s-B')]);
      },
    );
  });

  group('연결·이벤트 반영 — 완료 조건 9(데이터 없음 vs 연결 끊김 구분)', () {
    // P1(Ruling 208) — 이 그룹이 WS 로 실어 보내는 `received_at` 이 대부분
    // 이 값(2026-09-13T08:00:00Z)이다. `live_map_screen.dart` 가 이제
    // `clockProvider` 로 2분 유실을 판정하므로, 시험을 실제 실행 시각
    // (`DateTime.now()`)에 맡기면 실행 날짜에 따라 "유실"로 잘못 판정될
    // 수 있다 — 고정 시계를 기본값으로 준다.
    final fixedNow = DateTime.utc(2026, 9, 13, 8);

    Future<void> pumpConnected(WidgetTester tester, {Clock? clock}) async {
      await pumpScreen(
        tester,
        extraOverrides: [
          roleCapabilitiesProvider.overrideWithValue(
            RoleCapabilities.of(UserRole.student),
          ),
          myStudentIdProvider.overrideWith((ref) async => 's-1'),
          clockProvider.overrideWithValue(clock ?? _MutableClock(fixedNow)),
        ],
      );
      // myStudentIdProvider 의 FutureProvider 가 해소될 때까지 한 프레임.
      await tester.pump();
      await tester.pump();
      client.emit(WsConnectionState.connected);
      await tester.pump();
    }

    testWidgets('connected 인데 아직 이벤트가 없으면 "데이터 없음"만 뜨고 '
        '"연결 끊김"은 뜨지 않는다', (tester) async {
      await pumpConnected(tester);

      expect(find.text('아직 위치 정보가 없습니다'), findsOneWidget);
      expect(find.text(_gaveUpTitle), findsNothing);
      expect(
        client.subscribedDestinations,
        contains(WsChannel.studentRun('s-1')),
      );
    });

    testWidgets('position 이벤트를 받으면 위치 타일이 뜨고 "데이터 없음"은 사라진다', (
      tester,
    ) async {
      await pumpConnected(tester);

      client.deliver(
        _envelope(WsEventType.position, {
          'lat': 37.5,
          'lng': 127.0,
          'received_at': '2026-09-13T08:00:00Z',
          'current_stop_name': '정문 앞',
        }),
      );
      await tester.pump();

      expect(find.text('아직 위치 정보가 없습니다'), findsNothing);
      expect(find.text('정문 앞'), findsOneWidget);
      expect(find.text('마지막으로 지난 곳'), findsOneWidget);

      // ⚠ 2026-09-21 실측 — 이 줄이 UTC 를 그대로 벽시계로 보여줬다(한국시간
      // 20:03 에 "11:03 기준"). 서버가 주는 `received_at` 은 UTC 순간이고
      // `DateTime.parse` 는 그것을 UTC `DateTime` 으로 돌려준다.
      // 기대값을 `toLocal()` 로 만드는 이유는 시험기의 표준시를 바꿀 수단이
      // 부재하기 때문 — UTC 기계에서는 무해하게 통과하고 KST 에서 문다.
      final local = DateTime.utc(2026, 9, 13, 8).toLocal();
      String pad(int v) => v.toString().padLeft(2, '0');
      expect(
        find.text('${pad(local.hour)}:${pad(local.minute)} 기준'),
        findsOneWidget,
      );
    });

    // R32 P7 — 연결 끊김 띠에 다시 시도가 없어, 화면을 벗어났다 돌아오는 수밖에 없었다.
    testWidgets('연결 끊김 띠의 [다시 시도] 가 재연결을 건다', (tester) async {
      await pumpConnected(tester);
      client.emit(WsConnectionState.gaveUp);
      await tester.pump();
      final before = client.connectCalls;

      await tester.tap(find.text('다시 시도'));
      await tester.pump();

      expect(client.connectCalls, before + 1);
    });

    testWidgets('조회 권한 없음 띠에는 [다시 시도] 를 두지 않는다 — 다시 해도 거절된다', (tester) async {
      await pumpConnected(tester);
      client.forbid(WsChannel.studentRun('s-1'));
      await tester.pump();

      expect(find.text(WsConnectionNotice.forbiddenTitle), findsOneWidget);
      expect(find.text('다시 시도'), findsNothing);
    });

    testWidgets(
      'gaveUp(포기) 상태면 "연결 끊김"이 뜨고 "데이터 없음"과 동시에 뜨지 않는다',
      (tester) async {
        await pumpConnected(tester);
        client.emit(WsConnectionState.gaveUp);
        await tester.pump();

        expect(find.text(_gaveUpTitle), findsOneWidget);
        expect(find.text('아직 위치 정보가 없습니다'), findsNothing);
      },
    );

    testWidgets(
      '이 화면이 구독한 목적지가 거부되면 "조회 권한 없음"이 뜨고 '
      '"데이터 없음"과 동시에 뜨지 않는다',
      (tester) async {
        await pumpConnected(tester);
        client.forbid(WsChannel.studentRun('s-1'));
        await tester.pump();

        expect(find.text(WsConnectionNotice.forbiddenTitle), findsOneWidget);
        expect(find.text('아직 위치 정보가 없습니다'), findsNothing);
      },
    );

    testWidgets(
      '거부(forbidden) 후 연결이 되살아나도 같은 목적지를 다시 구독하지 '
      '않고 "조회 권한 없음"을 유지한다(팀 리드 우려 4 — 재구독 반복 방지)',
      (tester) async {
        await pumpConnected(tester);
        client.forbid(WsChannel.studentRun('s-1'));
        await tester.pump();
        client.callLog.clear();

        // baraeda_core 는 4403 세션 종료 뒤에도 자동 재연결을 시도한다
        // (공용 연결이 앱 전역 싱글턴이라 다른 화면을 위해 계속됨) — 그
        // 재연결 성공을 흉내낸다.
        client.emit(WsConnectionState.reconnecting);
        await tester.pump();
        client.emit(WsConnectionState.connected);
        await tester.pump();

        expect(find.text(WsConnectionNotice.forbiddenTitle), findsOneWidget);
        expect(
          client.callLog.contains(
            'subscribe:${WsChannel.studentRun('s-1')}',
          ),
          isFalse,
        );
      },
    );

    // Ruling 335 — 학생 채널은 인원수를 싣지 않고 앱도 표시하지 않는다(C-08 "탑승 인원 미표시").
    testWidgets('운행 시작·종료 이벤트를 받아도 탑승·하차 인원은 표시하지 않는다', (tester) async {
      await pumpConnected(tester);
      client
        ..deliver(
          _envelope(WsEventType.runStarted, {
            'run_status': 'moving',
            'started_at': '2026-09-13T08:00:00Z',
          }),
        )
        ..deliver(
          _envelope(WsEventType.runEnded, {
            'run_status': 'finished',
            'finished_at': '2026-09-13T09:00:00Z',
          }),
        );
      await tester.pump();

      // 종료 상태 — 운행 시작 · 종료 두 칸과 끝났다는 띠. 인원수 문구는 어디에도 없다.
      expect(find.text('운행 시작'), findsOneWidget);
      expect(find.text('운행 종료'), findsWidgets);
      expect(find.text('운행이 끝났어요'), findsOneWidget);
      expect(find.textContaining('명'), findsNothing);
    });

    testWidgets('reconnecting 상태면 데이터가 있어도 재연결 안내 배너가 함께 뜬다', (
      tester,
    ) async {
      await pumpConnected(tester);
      client.deliver(
        _envelope(WsEventType.runStarted, {
          'run_status': 'moving',
          'started_at': '2026-09-13T08:00:00Z',
          'auto_boarded_count': 3,
        }),
      );
      await tester.pump();

      client.emit(WsConnectionState.reconnecting);
      await tester.pump();

      expect(find.text(WsConnectionNotice.reconnectingTitle), findsOneWidget);
      expect(find.textContaining('운행 시작'), findsOneWidget);
    });
  });

  // R46-FIXCONN C-5 — 재연결 시도마다 `connecting` 이 와서, 끊김 중 지도(+배너)와
  // 전체 스피너가 시도 간격마다 번갈아 보였다. 스피너는 첫 진입의 첫 연결
  // 시도에만 쓴다 — 그 뒤의 재시도는 지도와 마지막 위치를 둔 채 재연결 안내로
  // 표시한다.
  group('재연결 시도 중 표시 — 스피너는 첫 진입만(C-5)', () {
    Future<void> pumpUntilFirstConnecting(WidgetTester tester) async {
      await pumpScreen(
        tester,
        extraOverrides: [
          roleCapabilitiesProvider.overrideWithValue(
            RoleCapabilities.of(UserRole.student),
          ),
          myStudentIdProvider.overrideWith((ref) async => 's-1'),
        ],
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('연결됐다 끊긴 뒤의 재시도(connecting)에는 스피너 대신 지도와 재연결 안내가 남는다', (
      tester,
    ) async {
      await pumpUntilFirstConnecting(tester);
      client.emit(WsConnectionState.connected);
      await tester.pump();
      client.deliver(
        _envelope(WsEventType.runStarted, {
          'run_status': 'moving',
          'started_at': '2026-09-13T08:00:00Z',
          'auto_boarded_count': 3,
        }),
      );
      await tester.pump();

      client
        ..emit(WsConnectionState.reconnecting)
        ..emit(WsConnectionState.connecting);
      await tester.pump();

      expect(find.byType(MapSheetSkeleton), findsNothing);
      expect(find.text(WsConnectionNotice.reconnectingTitle), findsOneWidget);
      expect(find.textContaining('운행 시작'), findsOneWidget);
    });

    testWidgets('한 번도 연결되지 못한 채 재시도해도 두 번째 connecting 부터는 스피너가 아니다', (
      tester,
    ) async {
      await pumpUntilFirstConnecting(tester);
      client.emit(WsConnectionState.connecting);
      await tester.pump();
      expect(find.byType(MapSheetSkeleton), findsOneWidget);

      client
        ..emit(WsConnectionState.reconnecting)
        ..emit(WsConnectionState.connecting);
      await tester.pump();

      // 받은 데이터가 아직 없으니 재연결 배너 대신 "데이터 없음" 화면이다 —
      // 요지는 시도마다 전체 스피너로 돌아가지 않는다는 것.
      expect(find.byType(MapSheetSkeleton), findsNothing);
      expect(find.text('아직 위치 정보가 없습니다'), findsOneWidget);
    });
  });

  // R46-FIXCONN C-9 — 재연결 때 REST 스냅샷을 다시 받아도 화면은 WS 로 한 번이라도
  // 받은 좌표를 우선해 스냅샷이 반영되지 않았다. 음영 중 버스가 움직였다면 다음
  // position 이 올 때까지 옛 좌표가 남는다 — 재연결 스냅샷이 더 새로우면 그것으로
  // 갈아 끼운다.
  group('재연결 뒤 위치 스냅샷 반영(C-9)', () {
    Future<void> pumpWithSnapshots(
      WidgetTester tester,
      List<BusPosition> snapshots,
    ) async {
      await pumpScreen(
        tester,
        busPositionRepository: _ScriptedBusPositionRepository(snapshots),
        extraOverrides: [
          roleCapabilitiesProvider.overrideWithValue(
            RoleCapabilities.of(UserRole.student),
          ),
          myStudentIdProvider.overrideWith((ref) async => 's-1'),
          // 스냅샷이 좌표를 주면 결석 대조를 위해 회차 목록을 읽는다 — 네트워크를 건드리지 않게 비운다.
          runsForStudentProvider.overrideWith((ref, id) async => const []),
          clockProvider.overrideWithValue(
            _MutableClock(DateTime.utc(2026, 9, 13, 8, 1)),
          ),
        ],
      );
      await tester.pump();
      await tester.pump();
      client.emit(WsConnectionState.connected);
      await tester.pump();
    }

    BusPosition snapshot({required String stop, required DateTime at}) =>
        BusPosition(
          runId: 'r-1',
          busNo: '1호차',
          runStatus: RunStatus.moving,
          lat: 37.6,
          lng: 127.1,
          receivedAt: at,
          currentStopName: stop,
        );

    testWidgets('재연결 스냅샷이 WS 로 받은 좌표보다 새로우면 그 좌표로 바뀐다', (tester) async {
      await pumpWithSnapshots(tester, [
        snapshot(stop: '첫 승하차지', at: DateTime.utc(2026, 9, 13, 8)),
        snapshot(stop: '음영 중 지난 승하차지', at: DateTime.utc(2026, 9, 13, 8, 0, 50)),
      ]);
      client.deliver(
        _envelope(WsEventType.position, {
          'lat': 37.5,
          'lng': 127.0,
          'received_at': '2026-09-13T08:00:00Z',
          'current_stop_name': '첫 승하차지',
        }),
      );
      await tester.pump();
      expect(find.textContaining('첫 승하차지'), findsOneWidget);

      client
        ..emit(WsConnectionState.reconnecting)
        ..emit(WsConnectionState.connected);
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('음영 중 지난 승하차지'), findsOneWidget);
      expect(find.textContaining('첫 승하차지'), findsNothing);

      // 유실 재표시 타이머를 남기지 않게 화면을 내린다.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('재연결 스냅샷이 더 오래됐으면 WS 좌표를 그대로 둔다', (tester) async {
      await pumpWithSnapshots(tester, [
        snapshot(stop: '옛 스냅샷', at: DateTime.utc(2026, 9, 13, 7, 59)),
      ]);
      client.deliver(
        _envelope(WsEventType.position, {
          'lat': 37.5,
          'lng': 127.0,
          'received_at': '2026-09-13T08:00:00Z',
          'current_stop_name': 'WS 최신 승하차지',
        }),
      );
      await tester.pump();

      client
        ..emit(WsConnectionState.reconnecting)
        ..emit(WsConnectionState.connected);
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('WS 최신 승하차지'), findsOneWidget);
      expect(find.textContaining('옛 스냅샷'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('연결·이벤트 반영 — P1(Ruling 208·349) 표시 중인 좌표의 신호 유실', () {
    final t0 = DateTime.utc(2026, 9, 13, 8);

    Future<void> pumpConnectedWithPosition(
      WidgetTester tester, {
      required Clock clock,
    }) async {
      await pumpScreen(
        tester,
        extraOverrides: [
          roleCapabilitiesProvider.overrideWithValue(
            RoleCapabilities.of(UserRole.student),
          ),
          myStudentIdProvider.overrideWith((ref) async => 's-1'),
          clockProvider.overrideWithValue(clock),
        ],
      );
      // myStudentIdProvider 의 FutureProvider 가 해소될 때까지 한 프레임.
      await tester.pump();
      await tester.pump();
      client.emit(WsConnectionState.connected);
      await tester.pump();
      client.deliver(
        _envelope(WsEventType.position, {
          'lat': 37.5,
          'lng': 127.0,
          'received_at': t0.toIso8601String(),
        }),
      );
      await tester.pump();
    }

    testWidgets('1분 59초가 지나도 "HH:mm 기준" 표지 표시를 유지한다', (tester) async {
      final clock = _MutableClock(t0);
      await pumpConnectedWithPosition(tester, clock: clock);
      expect(find.textContaining(' 기준'), findsOneWidget);

      // 실제로 재빌드를 일으키는 계기(백오프 재연결 시도)를 흉내낸다 —
      // 방송이 몇 초씩 끊기는 것(Ruling 349)은 연결 자체가 흔들리는 것과
      // 별개라 이 시험은 그 재시도가 화면을 다시 그리는 계기로만 쓴다.
      clock.value = t0.add(const Duration(minutes: 1, seconds: 59));
      client.emit(WsConnectionState.reconnecting);
      await tester.pump();

      expect(find.textContaining(' 기준'), findsOneWidget);
      expect(find.textContaining('마지막 확인 위치'), findsNothing);
    });

    testWidgets(
      '마지막 수신 후 2분이 지나면 "마지막 확인 위치 · N분 전" 으로 전환된다 — '
      '지금 코드는 연결이 끊기지 않는 한 "HH:mm 기준" 표지 로 그대로 남는다',
      (tester) async {
        final clock = _MutableClock(t0);
        await pumpConnectedWithPosition(tester, clock: clock);

        clock.value = t0.add(const Duration(minutes: 2));
        client.emit(WsConnectionState.reconnecting);
        await tester.pump();

        expect(find.textContaining('마지막 확인 위치 · 2분 전'), findsOneWidget);
        expect(find.textContaining(' 기준'), findsNothing);
      },
    );
  });

  group('F1(2026-09-26) — 다른 이벤트 없이 시간만 흐르는 경우의 자동 재표시', () {
    // 이 그룹은 위 그룹과 달리 `client.emit(...)` 을 전혀 부르지 않는다 —
    // WS 연결은 살아 있고 그 버스의 위치 방송만 끊긴(Ruling 349) 상황을
    // 재현한다. 지금 코드는 이 경우 화면을 다시 그리는 계기가 없어
    // "HH:mm 기준" 표지 가 무기한 남는다(브리프가 지적한 결함 그대로).
    final t0 = DateTime.utc(2026, 9, 13, 8);

    Future<void> pumpConnectedWithPosition(
      WidgetTester tester, {
      required Clock clock,
    }) async {
      await pumpScreen(
        tester,
        extraOverrides: [
          roleCapabilitiesProvider.overrideWithValue(
            RoleCapabilities.of(UserRole.student),
          ),
          myStudentIdProvider.overrideWith((ref) async => 's-1'),
          clockProvider.overrideWithValue(clock),
        ],
      );
      await tester.pump();
      await tester.pump();
      client.emit(WsConnectionState.connected);
      await tester.pump();
      client.deliver(
        _envelope(WsEventType.position, {
          'lat': 37.5,
          'lng': 127.0,
          'received_at': t0.toIso8601String(),
        }),
      );
      await tester.pump();
    }

    testWidgets(
      '다른 이벤트 없이 시간만 2분 지나면 자동으로 "마지막 확인 위치 · 2분 전" 으로 '
      '전환된다 — 1분 59초에는 "HH:mm 기준" 표지 를 유지한다',
      (tester) async {
        final clock = _MutableClock(t0);
        await pumpConnectedWithPosition(tester, clock: clock);
        expect(find.textContaining(' 기준'), findsOneWidget);

        clock.value = t0.add(const Duration(minutes: 1, seconds: 59));
        await tester.pump(const Duration(minutes: 1, seconds: 59));
        expect(find.textContaining(' 기준'), findsOneWidget);
        expect(find.textContaining('마지막 확인 위치'), findsNothing);

        clock.value = t0.add(const Duration(minutes: 2));
        await tester.pump(const Duration(seconds: 1));

        expect(find.textContaining('마지막 확인 위치 · 2분 전'), findsOneWidget);
        expect(find.textContaining(' 기준'), findsNothing);
      },
    );

    testWidgets('화면을 떠나면(dispose) 예약된 재표시 타이머가 남지 않는다', (
      tester,
    ) async {
      final clock = _MutableClock(t0);
      await pumpConnectedWithPosition(tester, clock: clock);
      expect(find.textContaining(' 기준'), findsOneWidget);

      // dispose 뒤 Timer 가 취소되지 않으면 flutter_test 가 테스트 종료 시
      // "A Timer is still pending" 로 이 시험 자체를 실패시킨다 — 별도
      // 단언 없이 dispose 만으로 검증이 성립한다.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('PF2(2026-09-26) — 새 좌표가 오면 예약을 다시 거는 동작(BRIEF-PF2 완료 조건 1)', () {
    // 위 F1 그룹은 좌표 하나가 2분을 넘기는 경우만 다룬다. 이 그룹은
    // `_scheduledForReceivedAt` 비교(코드 문서 참고)가 실제로 "새 좌표가
    // 오면 다시 예약한다"를 지키는지를 좌표 두 개(A·B)로 직접 고정한다.
    final t0 = DateTime.utc(2026, 9, 13, 8);

    Future<void> pumpConnected(
      WidgetTester tester, {
      required Clock clock,
    }) async {
      await pumpScreen(
        tester,
        extraOverrides: [
          roleCapabilitiesProvider.overrideWithValue(
            RoleCapabilities.of(UserRole.student),
          ),
          myStudentIdProvider.overrideWith((ref) async => 's-1'),
          clockProvider.overrideWithValue(clock),
        ],
      );
      // myStudentIdProvider 의 FutureProvider 가 해소될 때까지 한 프레임.
      await tester.pump();
      await tester.pump();
      client.emit(WsConnectionState.connected);
      await tester.pump();
    }

    void deliverPosition(DateTime receivedAt) {
      client.deliver(
        _envelope(WsEventType.position, {
          'lat': 37.5,
          'lng': 127.0,
          'received_at': receivedAt.toIso8601String(),
        }),
      );
    }

    testWidgets(
      '좌표 A 수신 1분30초 뒤 좌표 B 가 오면 예약이 B 기준으로 다시 걸린다 — '
      'A 기준 2분(=B 기준 30초)에는 아직 "HH:mm 기준" 표지, B 기준 2분에야 유실 문구로 전환된다',
      (tester) async {
        final clock = _MutableClock(t0);
        await pumpConnected(tester, clock: clock);
        deliverPosition(t0);
        await tester.pump();
        expect(find.textContaining(' 기준'), findsOneWidget);

        final tB = t0.add(const Duration(minutes: 1, seconds: 30));
        clock.value = tB;
        await tester.pump(const Duration(minutes: 1, seconds: 30));
        deliverPosition(tB);
        await tester.pump();
        expect(find.textContaining(' 기준'), findsOneWidget);

        // A 기준 2분(=B 기준 30초) — 재예약이 B 를 향해 걸렸다면 A 의
        // 예약은 이미 취소된 상태라 이 시점에는 아무것도 전환되지 않는다.
        clock.value = t0.add(const Duration(minutes: 2));
        await tester.pump(const Duration(seconds: 30));
        expect(find.textContaining(' 기준'), findsOneWidget);
        expect(find.textContaining('마지막 확인 위치'), findsNothing);

        // B 기준 2분 — 재예약이 실제로 B 를 향해 걸렸어야 이 시점에
        // 전환된다. A 의 예약만 살아 있는 결함이면 여기서 전환이
        // 일어나지 않는다(A 의 타이머는 이미 위에서 소진됐다).
        clock.value = tB.add(const Duration(minutes: 2));
        await tester.pump(const Duration(minutes: 1, seconds: 30));
        expect(find.textContaining('마지막 확인 위치 · 2분 전'), findsOneWidget);
        expect(find.textContaining(' 기준'), findsNothing);
      },
    );

    testWidgets(
      '같은 received_at 좌표가 재연결로 다시 와도 예약이 중복되지 않는다 — '
      '대기 중 타이머는 늘 1개다',
      (tester) async {
        final clock = _MutableClock(t0);
        await pumpConnected(tester, clock: clock);
        deliverPosition(t0);
        await tester.pump();

        // 재연결 재전송 — 같은 receivedAt 이 다시 온다.
        deliverPosition(t0);
        await tester.pump();

        // 타이머가 발화하기 전에 화면을 곧바로 떠난다. 재전송이 이전
        // 타이머를 취소하지 않고 새 타이머를 하나 더 만들었다면(중복
        // 예약) dispose 는 마지막 참조만 취소해 먼저 만든 것이 취소되지
        // 않은 채 남는다 — flutter_test 가 "A Timer is still pending"
        // 으로 이 시험을 실패시킨다.
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });

  group('F05-04·05 재연결 재구독 · 다음 회차 이벤트 초기화', () {
    Future<void> pumpConnected(
      WidgetTester tester, {
      RouteDetail? route,
    }) async {
      await pumpScreen(
        tester,
        route: route,
        extraOverrides: [
          roleCapabilitiesProvider.overrideWithValue(
            RoleCapabilities.of(UserRole.student),
          ),
          myStudentIdProvider.overrideWith((ref) async => 's-1'),
          clockProvider.overrideWithValue(
            _MutableClock(DateTime.utc(2026, 9, 13, 8)),
          ),
        ],
      );
      await tester.pump();
      await tester.pump();
      client.emit(WsConnectionState.connected);
      await tester.pump();
    }

    // 새 소켓은 이전 구독을 이어받지 않는다(`_doConnect`) — 재구독 책임은 화면에 있다.
    testWidgets('F05-04 연결이 끊겼다 되돌아오면 같은 목적지를 다시 구독한다', (tester) async {
      await pumpConnected(tester);
      final destination = WsChannel.studentRun('s-1');
      expect(
        client.callLog.where((e) => e == 'subscribe:$destination'),
        hasLength(1),
      );

      client.emit(WsConnectionState.reconnecting);
      await tester.pump();
      client.emit(WsConnectionState.connected);
      await tester.pump();

      expect(
        client.callLog.where((e) => e == 'subscribe:$destination'),
        hasLength(2),
      );
    });

    testWidgets('F05-05 다음 회차 운행 시작이 오면 앞 회차의 지난 곳·종료 상태를 지운다', (tester) async {
      await pumpConnected(tester);
      WebSocketEnvelope forRun(
        String runId,
        WsEventType e,
        Map<String, dynamic> p,
      ) => WebSocketEnvelope(
        event: e,
        eventWireValue: e.wireValue,
        runId: runId,
        occurredAt: DateTime(2026, 9, 13, 8),
        payload: p,
      );

      client
        ..deliver(
          forRun('r-1', WsEventType.runStarted, {
            'run_status': 'moving',
            'started_at': '2026-09-13T07:00:00Z',
          }),
        )
        ..deliver(
          forRun('r-1', WsEventType.stopArrived, {
            'stop_id': 'st-1',
            'seq': 1,
            'name': '정문',
            'arrived_at': '2026-09-13T07:10:00Z',
          }),
        );
      await tester.pump();
      // 달리는 중 — 마지막으로 지난 곳이 시트 칸에 있다.
      expect(find.text('정문'), findsOneWidget);
      expect(
        find.text(
          '마지막으로 지난 곳 · '
          '${formatClock(DateTime.utc(2026, 9, 13, 7, 10))}',
        ),
        findsOneWidget,
      );

      client.deliver(
        forRun('r-1', WsEventType.runEnded, {
          'run_status': 'finished',
          'finished_at': '2026-09-13T07:40:00Z',
        }),
      );
      await tester.pump();
      expect(find.text('운행이 끝났어요'), findsOneWidget);

      client.deliver(
        forRun('r-2', WsEventType.runStarted, {
          'run_status': 'moving',
          'started_at': '2026-09-13T15:00:00Z',
        }),
      );
      await tester.pump();

      expect(find.textContaining('운행 시작'), findsOneWidget);
      expect(find.text('운행이 끝났어요'), findsNothing);
      expect(find.text('정문'), findsNothing);
    });

    Map<String, Object> pos(double lat) => {
      'lat': lat,
      'lng': 127.0,
      'received_at': '2026-09-13T08:00:00Z',
    };
    MapSurface surface(WidgetTester tester) =>
        tester.widget<MapSurface>(find.byType(MapSurface));

    // R46 P3 — 버스가 움직여 화면 밖으로 나가도 지도가 따라간다. F05-09 는 "카메라를 고정하고
    // [버스 위치로] 로만 따라간다" 였고, 그러면 켜 두고 기다리는 동안 버스가 지도에서 사라졌다.
    testWidgets('R46 P3 새 좌표가 오면 지도 카메라가 버스를 따라간다', (tester) async {
      await pumpConnected(tester);

      client.deliver(_envelope(WsEventType.position, pos(37.5)));
      await tester.pump();
      expect(surface(tester).camera.lat, 37.5);

      client.deliver(_envelope(WsEventType.position, pos(37.6)));
      await tester.pump();
      expect(surface(tester).camera.lat, 37.6);
    });

    // F05-09 의 이유(2초마다 사용자가 옮긴 지도가 되돌아감)는 그대로 지킨다 — 손으로 만지면 따라가기를 멈춘다.
    testWidgets('R46 P3 사용자가 지도를 만지면 따라가기를 멈추고 [버스 위치로] 로 다시 켠다', (
      tester,
    ) async {
      await pumpConnected(tester);
      client.deliver(_envelope(WsEventType.position, pos(37.5)));
      await tester.pump();

      surface(tester).onUserGesture!();
      client.deliver(_envelope(WsEventType.position, pos(37.6)));
      await tester.pump();
      expect(
        surface(tester).camera.lat,
        37.5,
        reason: '사용자가 옮긴 자리를 덮어쓰지 않는다',
      );

      await tester.tap(find.text('버스 위치로'));
      await tester.pump();
      expect(surface(tester).camera.lat, 37.6);

      client.deliver(_envelope(WsEventType.position, pos(37.7)));
      await tester.pump();
      expect(surface(tester).camera.lat, 37.7, reason: '[버스 위치로] 뒤에는 다시 따라간다');
    });

    // R46 P1 — 지도에 버스 점만 있어 내 승하차지가 어디인지 알 수 없었다. 서버가 준 §3.10 좌표만 쓴다.
    testWidgets('R46 P1 내 승하차지를 지도 핀과 시트 칸으로 보여준다', (tester) async {
      await pumpConnected(tester, route: _routeWithMyStop());
      client.deliver(_envelope(WsEventType.position, pos(37.5)));
      await tester.pump();
      await tester.pump();

      // R49 — 응답의 승하차지 둘 다 번호 핀으로 그리고, 그중 내 승하차지만 강조 · 이름표를 단다.
      final stops = surface(
        tester,
      ).markers.where((m) => m.kind == MapMarkerKind.stop).toList();
      expect(stops, hasLength(2));
      final mine = stops.singleWhere((m) => m.mine);
      expect((mine.lat, mine.lng), (37.51, 127.02));
      expect(mine.label, '내 승하차지');
      expect(find.text('행복아파트 정문'), findsOneWidget);
      expect(find.text('내 승하차지'), findsOneWidget);
    });

    // C-08 — 학부모·학생 앱은 도착 예정 시각(ETA)·"몇 곳 전"·탑승 인원을 표시하지 않는다. 내 승하차지 핀을 더한 뒤에도
    // 같다: 서버가 준 좌표·이름만 쓰고 거리·시간을 새로 계산해 붙이지 않는다. 서버가 실수로 `eta`·인원을 실어 보내도
    // 화면에 나오지 않아야 하므로 payload 에 일부러 실어 렌더된 글자 전체를 훑는다.
    testWidgets('C-08 지도 화면 어디에도 ETA·몇 곳 전·탑승 인원 문구가 없다', (tester) async {
      await pumpConnected(tester, route: _routeWithMyStop());
      client
        ..deliver(
          _envelope(WsEventType.runStarted, {
            'run_status': 'moving',
            'started_at': '2026-09-13T07:50:00Z',
            'auto_boarded_count': 7,
          }),
        )
        ..deliver(
          _envelope(WsEventType.position, {
            ...pos(37.5),
            'current_stop_name': '앞 승하차지',
            'eta': '2026-09-13T08:07:00Z',
            'boarded_count': 7,
          }),
        );
      await tester.pump();
      await tester.pump();

      final rendered = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .join('\n');
      // 핀·내 승하차지 문구가 실제로 그려진 상태에서만 "없다" 가 의미가 있다.
      expect(rendered, contains('행복아파트 정문'));
      expect(rendered, contains('내 승하차지'));
      expect(rendered, contains('앞 승하차지'));
      expect(rendered, contains('마지막으로 지난 곳'));
      expect(
        rendered,
        isNot(matches(RegExp(r'도착 예정|ETA|예상|곳 전|정거장 전|분 후|탑승 인원|\d+\s*명'))),
      );
      // 문구가 아니라 값도 본다 — 서버가 실어 보낸 eta(08:07 UTC)를 날것으로든 기기 표준시로든 그리면 안 된다.
      final etaLocal = DateTime.utc(2026, 9, 13, 8, 7).toLocal();
      final etaClock =
          '${etaLocal.hour.toString().padLeft(2, '0')}:'
          '${etaLocal.minute.toString().padLeft(2, '0')}';
      expect(rendered, isNot(contains('2026-09-13T08:07')));
      expect(rendered, isNot(contains('08:07')));
      expect(rendered, isNot(contains(etaClock)));
    });

    testWidgets('R46 P1 노선을 못 받거나 좌표가 없으면 버스만 그리고 오류 띠를 더하지 않는다', (
      tester,
    ) async {
      await pumpConnected(tester); // 노선 가짜가 실패를 돌려준다
      client.deliver(_envelope(WsEventType.position, pos(37.5)));
      await tester.pump();
      await tester.pump();

      expect(surface(tester).markers.map((m) => m.kind), [MapMarkerKind.bus]);
      expect(find.textContaining('내 승하차지'), findsNothing);
      expect(find.byType(AlertBanner), findsNothing);
    });
  });

  // R48 `Ruling 821` — 전체 지도 화면도 §3.11 의 delay · started_at · finished_at 을
  // 그린다.
  // WebSocket 이벤트(`run_started` · `run_ended`)를 놓치고 들어와도 시각이 비지 않고, 지연 띠는 delay
  // 에서 온다.
  group('R48 §3.11 스냅샷의 지연 띠 · 운행 시각', () {
    final startedAt = DateTime.utc(2026, 9, 13, 3, 5);
    final finishedAt = DateTime.utc(2026, 9, 13, 3, 52);

    Future<void> pumpWithSnapshot(
      WidgetTester tester,
      BusPosition snapshot,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpScreen(
        tester,
        busPositionRepository: _ScriptedBusPositionRepository([snapshot]),
        extraOverrides: [
          roleCapabilitiesProvider.overrideWithValue(
            RoleCapabilities.of(UserRole.student),
          ),
          myStudentIdProvider.overrideWith((ref) async => 's-1'),
          // 스냅샷은 당일 결석 대조(`runsForStudentProvider`)까지 끝나야 화면에 반영된다 — 진짜 네트워크를
          // 기다리지 않게 막는다.
          runsForStudentProvider.overrideWith(
            (ref, id) async => const <StudentRun>[],
          ),
          clockProvider.overrideWithValue(
            _MutableClock(DateTime.utc(2026, 9, 13, 3, 14)),
          ),
        ],
      );
      await tester.pump();
      await tester.pump();
      client.emit(WsConnectionState.connected);
      await tester.pumpAndSettle();
    }

    BusPosition snapshot({
      RunStatus status = RunStatus.moving,
      BusDelay? delay,
      DateTime? started,
      DateTime? finished,
    }) => BusPosition(
      runId: 'r-1',
      busNo: '2호차',
      runStatus: status,
      lat: 37.5,
      lng: 127,
      receivedAt: DateTime.utc(2026, 9, 13, 3, 14),
      currentStopName: '정문 앞',
      currentStopArrivedAt: DateTime(2026, 9, 13, 12, 9),
      startedAt: started,
      finishedAt: finished,
      delay: delay,
    );

    testWidgets('delay 가 있으면 "10분 늦어요" 띠와 사유가 나온다', (tester) async {
      await pumpWithSnapshot(
        tester,
        snapshot(
          delay: BusDelay(
            minutes: 10,
            reason: '교통 체증',
            sentAt: DateTime.utc(2026, 9, 13, 3, 12),
          ),
        ),
      );

      expect(find.text('10분 늦어요'), findsOneWidget);
      expect(find.text('교통 체증'), findsOneWidget);
    });

    testWidgets('delay 가 null 이면 띠가 없다', (tester) async {
      await pumpWithSnapshot(tester, snapshot());

      expect(find.textContaining('늦어요'), findsNothing);
    });

    testWidgets('WebSocket 이벤트를 못 받았어도 REST 의 started_at 으로 운행 시작 시각을 그린다', (
      tester,
    ) async {
      await pumpWithSnapshot(tester, snapshot(started: startedAt));

      // 이벤트(`run_started`)는 한 번도 오지 않았다 — 시각은 스냅샷에서 온다.
      expect(find.textContaining('운행 시작'), findsOneWidget);
    });

    testWidgets('finished_at 이 있으면 운행 종료 시각을 그린다', (tester) async {
      await pumpWithSnapshot(
        tester,
        snapshot(
          status: RunStatus.finished,
          started: startedAt,
          finished: finishedAt,
        ),
      );

      expect(find.text('운행 종료'), findsWidgets);
      expect(
        find.text('${formatClock(finishedAt)} 에 운행을 마쳤어요.'),
        findsOneWidget,
      );
    });

    testWidgets('마지막으로 지난 곳에는 도착 시각이 붙는다 — 12:09', (tester) async {
      await pumpWithSnapshot(tester, snapshot());

      expect(find.textContaining('마지막으로 지난 곳 · 12:09'), findsOneWidget);
    });
  });

  // R48 시안 `live-map*` — 상태마다 시트 모양이 다르다. 한 모양이 다른 모양의 글자를 섞어 쓰면(예: 종료인데 "이동
  // 중")
  // 학부모가 버스가 아직 달리는 줄 안다.
  group('R48 시트 — 상태마다 모양이 다르다', () {
    final started = DateTime.utc(2026, 10, 4, 3, 5);
    final departAt = DateTime.utc(2026, 10, 4, 5, 40);
    final clockNow = DateTime.utc(2026, 10, 4, 3, 14);

    StudentRun run({
      RunStatus status = RunStatus.moving,
      bool confirmed = true,
      DateTime? depart,
    }) => StudentRun(
      runId: 'r-1',
      direction: RunDirection.toAcademy,
      busNo: '2호차',
      departTime: depart ?? started,
      runStatus: status,
      confirmed: confirmed,
      riding: true,
      riderStatus: RiderStatus.waiting,
      stop: const RunStop(stopId: 'st-mine', name: '행복마을 입구'),
      changeQuotaLeft: 1,
    );

    BusPosition snapshot({
      RunStatus status = RunStatus.moving,
      bool withPosition = true,
      DateTime? lastSeenAt,
      DateTime? startedAt,
      DateTime? finishedAt,
      BusDelay? delay,
    }) => BusPosition(
      runId: 'r-1',
      busNo: '2호차',
      runStatus: status,
      lat: withPosition ? 37.5 : null,
      lng: withPosition ? 127 : null,
      receivedAt: withPosition ? clockNow : null,
      lastSeenAt: lastSeenAt,
      currentStopName: withPosition ? '중앙공원 앞' : null,
      currentStopArrivedAt: withPosition
          ? DateTime.utc(2026, 10, 4, 3, 9)
          : null,
      startedAt: startedAt,
      finishedAt: finishedAt,
      delay: delay,
    );

    Future<void> pumpParent(
      WidgetTester tester, {
      required BusPositionRepository repository,
      List<StudentRun> runs = const [],
      RouteDetail? route,
      bool settle = true,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpScreen(
        tester,
        busPositionRepository: repository,
        route: route,
        extraOverrides: [
          roleCapabilitiesProvider.overrideWithValue(
            RoleCapabilities.of(UserRole.parent),
          ),
          myStudentsProvider.overrideWith(
            (ref) async => [
              Student(studentId: 's-1', name: '이하준', linkedAt: _linkedAt),
            ],
          ),
          runsForStudentProvider.overrideWith((ref, id) async => runs),
          clockProvider.overrideWithValue(_MutableClock(clockNow)),
        ],
      );
      await tester.pump();
      await tester.pump();
      client.emit(WsConnectionState.connected);
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
        await tester.pump();
      }
    }

    testWidgets('달리는 중 — 이동 중 칩 · 시각 표지 · 지도 단추 · 지연 띠, 다른 상태의 글자는 없다', (
      tester,
    ) async {
      await pumpParent(
        tester,
        repository: _ScriptedBusPositionRepository([
          snapshot(
            startedAt: started,
            delay: BusDelay(minutes: 10, reason: '교통 체증', sentAt: clockNow),
          ),
        ]),
        runs: [run()],
        route: _routeWithMyStop(),
      );

      expect(find.byType(MapSurface), findsOneWidget);
      expect(find.text('이하준 등원 · 2호차'), findsOneWidget);
      expect(find.text('이동 중'), findsOneWidget);
      expect(find.text('${formatClock(clockNow)} 기준'), findsOneWidget);
      expect(find.text('${formatClock(started)} 운행 시작'), findsOneWidget);
      expect(find.text('10분 늦어요'), findsOneWidget);
      expect(find.text('버스 위치로'), findsOneWidget);
      expect(find.text('내 승하차지로'), findsOneWidget);
      expect(find.text('중앙공원 앞'), findsOneWidget);
      expect(find.text('신호 없음'), findsNothing);
      expect(find.text('종료'), findsNothing);
      expect(find.text('연결 끊김'), findsNothing);
      expect(find.text('버스가 아직 출발 전이에요'), findsNothing);
    });

    testWidgets('신호 없음 — 지도 없이 앰버 이름표 · 끊겼다는 띠 · 마지막으로 확인한 시각', (tester) async {
      final lastSeen = clockNow.subtract(const Duration(minutes: 4));
      await pumpParent(
        tester,
        repository: _ScriptedBusPositionRepository([
          snapshot(
            withPosition: false,
            lastSeenAt: lastSeen,
            startedAt: started,
          ),
        ]),
        runs: [run()],
      );

      expect(find.text('신호 없음'), findsOneWidget);
      expect(find.text('위치 신호가 끊겼어요'), findsOneWidget);
      expect(find.text('마지막 확인 위치 · 4분 전'), findsOneWidget);
      expect(find.text('마지막으로 확인한 시각'), findsOneWidget);
      expect(find.text(formatClock(lastSeen)), findsOneWidget);
      // 좌표가 없는데 지도를 그릴 근거가 없다 — 지도 · 지도 단추 · 이동 중 칩이 모두 없다.
      expect(find.byType(MapSurface), findsNothing);
      expect(find.text('버스 위치로'), findsNothing);
      expect(find.text('이동 중'), findsNothing);
      expect(find.text('운행이 끝났어요'), findsNothing);
    });

    testWidgets('운행 전 — 지도 대신 출발 시각 안내 · 확정 전 칩 · 노선 미리 보기', (tester) async {
      await pumpParent(
        tester,
        repository: _ScriptedBusPositionRepository([
          snapshot(status: RunStatus.idle, withPosition: false),
        ]),
        runs: [run(status: RunStatus.idle, confirmed: false, depart: departAt)],
      );

      expect(find.text('버스가 아직 출발 전이에요'), findsOneWidget);
      expect(find.textContaining(formatClock(departAt)), findsWidgets);
      expect(find.text('확정 전'), findsOneWidget);
      expect(
        find.textContaining(
          '${formatClock(departAt.subtract(const Duration(minutes: 30)))} '
          '에 노선이 확정돼요',
        ),
        findsOneWidget,
      );
      expect(find.text('노선 미리 보기'), findsOneWidget);
      expect(find.byType(MapSurface), findsNothing);
      expect(find.text('이동 중'), findsNothing);
      expect(find.text('노선 자세히 보기'), findsNothing);
      expect(find.text('위치 신호가 끊겼어요'), findsNothing);
    });

    testWidgets('운행 전이라도 노선이 확정됐으면 "확정" 칩이고 확정 시각 안내는 없다', (tester) async {
      await pumpParent(
        tester,
        repository: _ScriptedBusPositionRepository([
          snapshot(status: RunStatus.confirmed, withPosition: false),
        ]),
        runs: [run(status: RunStatus.confirmed, depart: departAt)],
      );

      expect(find.text('확정'), findsOneWidget);
      expect(find.text('확정 전'), findsNothing);
      expect(find.textContaining('에 노선이 확정돼요'), findsNothing);
    });

    testWidgets('종료 — 종료 칩 · 끝났다는 띠 · 시작/종료 두 칸, 달리는 중 표시는 없다', (tester) async {
      final finished = DateTime.utc(2026, 10, 4, 3, 52);
      await pumpParent(
        tester,
        repository: _ScriptedBusPositionRepository([
          snapshot(
            status: RunStatus.finished,
            withPosition: false,
            startedAt: started,
            finishedAt: finished,
          ),
        ]),
        runs: [run(status: RunStatus.finished)],
      );

      expect(find.text('종료'), findsOneWidget);
      expect(find.text('운행이 끝났어요'), findsOneWidget);
      expect(find.text(formatClock(started)), findsOneWidget);
      expect(find.text(formatClock(finished)), findsOneWidget);
      expect(find.text('운행 시작'), findsOneWidget);
      expect(find.text('운행 종료'), findsWidgets);
      expect(find.text('이동 중'), findsNothing);
      expect(find.text('신호 없음'), findsNothing);
      expect(find.text('버스 위치로'), findsNothing);
      expect(find.textContaining(' 기준'), findsNothing);
    });

    testWidgets('연결 끊김 — 마지막으로 받은 시각 이름표 · 다시 시도, 이동 중 칩은 없다', (tester) async {
      await pumpParent(
        tester,
        repository: _ScriptedBusPositionRepository([snapshot()]),
        runs: [run()],
      );
      client.emit(WsConnectionState.gaveUp);
      await tester.pumpAndSettle();

      expect(find.text('연결 끊김'), findsOneWidget);
      expect(find.text(_gaveUpTitle), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
      expect(find.text('마지막 갱신 ${formatClock(clockNow)}'), findsOneWidget);
      expect(find.text('이동 중'), findsNothing);
      expect(find.text('버스 위치로'), findsNothing);
    });

    testWidgets('불러오는 중 — 시트 뼈대만 있고 [노선 자세히 보기] 는 꺼져 있다', (tester) async {
      await pumpParent(
        tester,
        repository: _NeverBusPositionRepository(),
        settle: false,
      );

      expect(find.byType(MapSheetSkeleton), findsOneWidget);
      final button = tester.widget<BaraedaButton>(
        find.widgetWithText(BaraedaButton, '노선 자세히 보기'),
      );
      expect(button.onPressed, isNull);
      expect(find.text('이동 중'), findsNothing);
      expect(find.text('버스가 아직 출발 전이에요'), findsNothing);
    });
  });

  // R49 `Ruling 831` · `832` — 지도에 표시 범위 승하차지의 번호 마커와 경로선, 문구에 도착지 이름.
  group('R49 지도 — 노선선 · 번호 · 도착지 이름', () {
    final started = DateTime.utc(2026, 10, 5, 3, 5);
    final finished = DateTime.utc(2026, 10, 5, 3, 52);
    final clockNow = DateTime.utc(2026, 10, 5, 3, 14);
    final road = [
      (lat: 37.501, lng: 126.701),
      (lat: 37.502, lng: 126.703),
      (lat: 37.504, lng: 126.704),
      (lat: 37.505, lng: 126.706),
    ];

    // 응답이 표시 범위(승차지 이전 2개 · 승차지 · 하차지)만 줬다고 가정한 3·4·5 번. 4번이 내 승하차지다.
    RouteDetail route({
      List<({double lat, double lng})>? roadPath,
      bool arrived = false,
    }) => RouteDetail(
      runId: 'r-1',
      busNo: '2호차',
      departTime: started,
      confirmed: true,
      driver: const RouteDriver(name: null),
      escort: const RouteEscort(name: null, phone: null),
      myStopId: 'st-mine',
      roadPath: roadPath ?? road,
      stops: [
        RouteStop(
          stopId: 'st-3',
          seq: 3,
          name: '중앙공원 앞',
          address: null,
          lat: 37.501,
          lng: 126.701,
          arrivedAt: arrived ? DateTime.utc(2026, 10, 5, 3, 9) : null,
        ),
        RouteStop(
          stopId: 'st-mine',
          seq: 4,
          name: '행복마을 입구',
          address: null,
          lat: 37.504,
          lng: 126.704,
          arrivedAt: arrived ? DateTime.utc(2026, 10, 5, 3, 20) : null,
        ),
        const RouteStop(
          stopId: 'st-5',
          seq: 5,
          name: '하늘수학',
          address: null,
          lat: 37.505,
          lng: 126.706,
        ),
      ],
    );

    StudentRun run({RunDirection direction = RunDirection.toAcademy}) =>
        StudentRun(
          runId: 'r-1',
          direction: direction,
          busNo: '2호차',
          departTime: started,
          runStatus: RunStatus.moving,
          confirmed: true,
          riding: true,
          riderStatus: RiderStatus.waiting,
          stop: const RunStop(stopId: 'st-mine', name: '행복마을 입구'),
          changeQuotaLeft: 1,
        );

    BusPosition snapshot({
      RunStatus status = RunStatus.moving,
      bool withPosition = true,
    }) => BusPosition(
      runId: 'r-1',
      busNo: '2호차',
      runStatus: status,
      lat: withPosition ? 37.5025 : null,
      lng: withPosition ? 126.7035 : null,
      receivedAt: withPosition ? clockNow : null,
      startedAt: started,
      finishedAt: status == RunStatus.finished ? finished : null,
    );

    Future<void> pumpMap(
      WidgetTester tester, {
      required BusPosition position,
      RouteDetail? routeDetail,
      String? academyName,
      RunDirection direction = RunDirection.toAcademy,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      _FakeRouteRepository.requestedRunIds.clear();
      await pumpScreen(
        tester,
        busPositionRepository: _ScriptedBusPositionRepository([position]),
        route: routeDetail,
        academyName: academyName,
        extraOverrides: [
          roleCapabilitiesProvider.overrideWithValue(
            RoleCapabilities.of(UserRole.parent),
          ),
          myStudentsProvider.overrideWith(
            (ref) async => [
              Student(studentId: 's-1', name: '이하준', linkedAt: _linkedAt),
            ],
          ),
          runsForStudentProvider.overrideWith(
            (ref, id) async => [run(direction: direction)],
          ),
          clockProvider.overrideWithValue(_MutableClock(clockNow)),
        ],
      );
      await tester.pump();
      await tester.pump();
      client.emit(WsConnectionState.connected);
      await tester.pumpAndSettle();
    }

    MapSurface surface(WidgetTester tester) =>
        tester.widget<MapSurface>(find.byType(MapSurface));

    testWidgets('달리는 중 — road_path 선 1개와 표시 승하차지 수만큼 번호 마커(번호는 seq)를 그린다', (
      tester,
    ) async {
      await pumpMap(
        tester,
        position: snapshot(),
        routeDetail: route(),
      );

      final map = surface(tester);
      expect(map.polylines, hasLength(1));
      expect(map.polylines.single.dashed, isFalse);
      expect(map.polylines.single.points, road);
      final stops = map.markers
          .where((m) => m.kind == MapMarkerKind.stop)
          .toList();
      expect(stops.map((m) => m.seq), [3, 4, 5]);
      expect(
        map.markers.where((m) => m.kind == MapMarkerKind.bus),
        hasLength(1),
      );
    });

    testWidgets('달리는 중 — 내 승하차지만 강조하고 "내 승하차지" 이름표를 단다', (tester) async {
      await pumpMap(tester, position: snapshot(), routeDetail: route());

      final mine = surface(tester).markers.where((m) => m.mine).toList();
      expect(mine.map((m) => m.seq), [4]);
      expect(mine.single.label, '내 승하차지');
    });

    testWidgets('달리는 중 — road_path 가 비면 표시 승하차지를 점선으로 잇는다', (tester) async {
      await pumpMap(
        tester,
        position: snapshot(),
        routeDetail: route(roadPath: const []),
      );

      final line = surface(tester).polylines.single;
      expect(line.dashed, isTrue);
      expect(line.points, hasLength(3));
    });

    testWidgets('응답에 없는 승하차지는 그리지 않는다 — 번호 3·4·5 만 있다', (tester) async {
      await pumpMap(tester, position: snapshot(), routeDetail: route());

      final seqs = surface(tester).markers.map((m) => m.seq).nonNulls.toList();
      expect(seqs, [3, 4, 5]);
    });

    testWidgets('노선을 못 받으면 선도 번호도 없이 버스만 그린다', (tester) async {
      await pumpMap(tester, position: snapshot());

      final map = surface(tester);
      expect(map.polylines, isEmpty);
      expect(map.markers.map((m) => m.kind), [MapMarkerKind.bus]);
    });

    testWidgets('종료 — 좌표가 없어도 지나온 구간(선)과 번호 마커를 그리고 노선에 맞춘다', (
      tester,
    ) async {
      await pumpMap(
        tester,
        position: snapshot(status: RunStatus.finished, withPosition: false),
        routeDetail: route(arrived: true),
        academyName: '하늘수학',
      );

      final map = surface(tester);
      expect(map.polylines, hasLength(1));
      expect(map.polylines.single.passed, isTrue);
      final stops = map.markers.where((m) => m.kind == MapMarkerKind.stop);
      expect(stops.map((m) => m.seq), [3, 4, 5]);
      expect(map.markers.where((m) => m.kind == MapMarkerKind.bus), isEmpty);
      expect(map.fitToContent, isTrue);
    });

    testWidgets('종료 — 지나간 승하차지(arrived_at 있음)만 지나간 모양이다', (tester) async {
      await pumpMap(
        tester,
        position: snapshot(status: RunStatus.finished, withPosition: false),
        routeDetail: route(arrived: true),
      );

      final byStop = {
        for (final m in surface(tester).markers.where((m) => m.seq != null))
          m.seq: m.stopState,
      };
      expect(byStop, {
        3: MapStopState.passed,
        4: MapStopState.passed,
        5: MapStopState.upcoming,
      });
    });

    testWidgets('종료 + 노선을 못 받으면 지도 없이 회색 면이다(기존 동작)', (tester) async {
      await pumpMap(
        tester,
        position: snapshot(status: RunStatus.finished, withPosition: false),
      );

      expect(find.byType(MapSurface), findsNothing);
      expect(find.text('운행이 끝났어요'), findsOneWidget);
    });

    testWidgets('종료된 회차도 그 회차의 노선을 읽는다 — 요청에 run_id 가 실린다', (tester) async {
      await pumpMap(
        tester,
        position: snapshot(status: RunStatus.finished, withPosition: false),
        routeDetail: route(arrived: true),
      );

      expect(_FakeRouteRepository.requestedRunIds, isNotEmpty);
      expect(_FakeRouteRepository.requestedRunIds.toSet(), {'r-1'});
    });

    testWidgets('등원 종료 — 학원 이름이 "도착" 줄과 종료 띠에 들어간다', (tester) async {
      await pumpMap(
        tester,
        position: snapshot(status: RunStatus.finished, withPosition: false),
        routeDetail: route(arrived: true),
        academyName: '하늘수학',
      );

      expect(find.text('하늘수학 도착'), findsOneWidget);
      expect(
        find.text('${formatClock(finished)} 하늘수학에 도착했어요.'),
        findsOneWidget,
      );
    });

    testWidgets('하원 종료 — 내 승하차지 이름이 들어간다', (tester) async {
      await pumpMap(
        tester,
        position: snapshot(status: RunStatus.finished, withPosition: false),
        routeDetail: route(arrived: true),
        academyName: '하늘수학',
        direction: RunDirection.fromAcademy,
      );

      expect(find.text('행복마을 입구 도착'), findsOneWidget);
      expect(
        find.text('${formatClock(finished)} 행복마을 입구에 도착했어요.'),
        findsOneWidget,
      );
      expect(find.textContaining('하늘수학'), findsNothing);
    });

    testWidgets('종료 — 이름을 못 얻으면 이름 없는 R48 문구로 떨어진다', (tester) async {
      await pumpMap(
        tester,
        position: snapshot(status: RunStatus.finished, withPosition: false),
        routeDetail: route(arrived: true),
      );

      expect(find.text('${formatClock(finished)} 에 운행을 마쳤어요.'), findsOneWidget);
      expect(find.textContaining('도착했어요'), findsNothing);
      expect(find.textContaining(' 도착'), findsNothing);
    });

    testWidgets('달리는 중 — 시트 부제가 "도착지 가는 길 · 시각 운행 시작" 이다', (tester) async {
      await pumpMap(
        tester,
        position: snapshot(),
        routeDetail: route(),
        academyName: '하늘수학',
      );

      expect(
        find.text('하늘수학 가는 길 · ${formatClock(started)} 운행 시작'),
        findsOneWidget,
      );
    });

    testWidgets('달리는 중 — 이름을 못 얻으면 "시각 운행 시작" 만 남는다', (tester) async {
      await pumpMap(tester, position: snapshot(), routeDetail: route());

      expect(find.text('${formatClock(started)} 운행 시작'), findsOneWidget);
      expect(find.textContaining('가는 길'), findsNothing);
    });
  });

}
