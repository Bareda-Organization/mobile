import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/role_policy.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/live_map/domain/bus_position.dart';
import 'package:parent_app/features/live_map/domain/bus_position_repository.dart';
import 'package:parent_app/features/live_map/presentation/live_map_screen.dart';
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
  _FakeWsClient()
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

  @override
  void connect() {
    // 실 소켓을 열지 않는다 — 시험은 [emit] 으로 상태 전이를 직접 민다.
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
  _MutableClock(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

final _linkedAt = DateTime(2026);

void main() {
  late _FakeWsClient client;

  setUp(() {
    client = _FakeWsClient();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<Override> extraOverrides,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          webSocketClientProvider.overrideWithValue(client),
          busPositionRepositoryProvider.overrideWithValue(
            _FakeBusPositionRepository(),
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

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('연결 끊김'), findsNothing);
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

      expect(find.text('자녀 선택'), findsNothing);
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

      expect(find.text('자녀 선택'), findsOneWidget);
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
      expect(find.text('연결 끊김'), findsNothing);
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
      expect(find.textContaining('가장 가까운 승하차지: 정문 앞'), findsOneWidget);

      // ⚠ 2026-09-21 실측 — 이 줄이 UTC 를 그대로 벽시계로 보여줬다(한국시간
      // 20:03 에 "11:03:23 기준"). 서버가 주는 `received_at` 은 UTC 순간이고
      // `DateTime.parse` 는 그것을 UTC `DateTime` 으로 돌려준다.
      // 기대값을 `toLocal()` 로 만드는 이유는 시험기의 표준시를 바꿀 수단이
      // 부재하기 때문 — UTC 기계에서는 무해하게 통과하고 KST 에서 문다.
      final local = DateTime.utc(2026, 9, 13, 8).toLocal();
      String pad(int v) => v.toString().padLeft(2, '0');
      expect(
        find.textContaining(
          '현재 위치 · ${pad(local.hour)}:${pad(local.minute)}:'
          '${pad(local.second)} 기준',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'gaveUp(포기) 상태면 "연결 끊김"이 뜨고 "데이터 없음"과 동시에 뜨지 않는다',
      (tester) async {
        await pumpConnected(tester);
        client.emit(WsConnectionState.gaveUp);
        await tester.pump();

        expect(find.text('연결 끊김'), findsOneWidget);
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

        expect(find.text('조회 권한 없음'), findsOneWidget);
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

        expect(find.text('조회 권한 없음'), findsOneWidget);
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

      expect(find.textContaining('운행 시작'), findsOneWidget);
      expect(find.textContaining('운행 종료'), findsOneWidget);
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

      expect(find.text('재연결 시도 중입니다'), findsOneWidget);
      expect(find.textContaining('운행 시작'), findsOneWidget);
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

    testWidgets('1분 59초가 지나도 "현재 위치" 표시를 유지한다', (tester) async {
      final clock = _MutableClock(t0);
      await pumpConnectedWithPosition(tester, clock: clock);
      expect(find.textContaining('현재 위치'), findsOneWidget);

      // 실제로 재빌드를 일으키는 계기(백오프 재연결 시도)를 흉내낸다 —
      // 방송이 몇 초씩 끊기는 것(Ruling 349)은 연결 자체가 흔들리는 것과
      // 별개라 이 시험은 그 재시도가 화면을 다시 그리는 계기로만 쓴다.
      clock.value = t0.add(const Duration(minutes: 1, seconds: 59));
      client.emit(WsConnectionState.reconnecting);
      await tester.pump();

      expect(find.textContaining('현재 위치'), findsOneWidget);
      expect(find.textContaining('마지막 확인 위치'), findsNothing);
    });

    testWidgets(
      '마지막 수신 후 2분이 지나면 "마지막 확인 위치 · N분 전" 으로 전환된다 — '
      '지금 코드는 연결이 끊기지 않는 한 "현재 위치" 로 그대로 남는다',
      (tester) async {
        final clock = _MutableClock(t0);
        await pumpConnectedWithPosition(tester, clock: clock);

        clock.value = t0.add(const Duration(minutes: 2));
        client.emit(WsConnectionState.reconnecting);
        await tester.pump();

        expect(find.textContaining('마지막 확인 위치 · 2분 전'), findsOneWidget);
        expect(find.textContaining('현재 위치'), findsNothing);
      },
    );
  });

  group('F1(2026-09-26) — 다른 이벤트 없이 시간만 흐르는 경우의 자동 재표시', () {
    // 이 그룹은 위 그룹과 달리 `client.emit(...)` 을 전혀 부르지 않는다 —
    // WS 연결은 살아 있고 그 버스의 위치 방송만 끊긴(Ruling 349) 상황을
    // 재현한다. 지금 코드는 이 경우 화면을 다시 그리는 계기가 없어
    // "현재 위치" 가 무기한 남는다(브리프가 지적한 결함 그대로).
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
      '전환된다 — 1분 59초에는 "현재 위치" 를 유지한다',
      (tester) async {
        final clock = _MutableClock(t0);
        await pumpConnectedWithPosition(tester, clock: clock);
        expect(find.textContaining('현재 위치'), findsOneWidget);

        clock.value = t0.add(const Duration(minutes: 1, seconds: 59));
        await tester.pump(const Duration(minutes: 1, seconds: 59));
        expect(find.textContaining('현재 위치'), findsOneWidget);
        expect(find.textContaining('마지막 확인 위치'), findsNothing);

        clock.value = t0.add(const Duration(minutes: 2));
        await tester.pump(const Duration(seconds: 1));

        expect(find.textContaining('마지막 확인 위치 · 2분 전'), findsOneWidget);
        expect(find.textContaining('현재 위치'), findsNothing);
      },
    );

    testWidgets('화면을 떠나면(dispose) 예약된 재표시 타이머가 남지 않는다', (
      tester,
    ) async {
      final clock = _MutableClock(t0);
      await pumpConnectedWithPosition(tester, clock: clock);
      expect(find.textContaining('현재 위치'), findsOneWidget);

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
      'A 기준 2분(=B 기준 30초)에는 아직 "현재 위치", B 기준 2분에야 유실 문구로 전환된다',
      (tester) async {
        final clock = _MutableClock(t0);
        await pumpConnected(tester, clock: clock);
        deliverPosition(t0);
        await tester.pump();
        expect(find.textContaining('현재 위치'), findsOneWidget);

        final tB = t0.add(const Duration(minutes: 1, seconds: 30));
        clock.value = tB;
        await tester.pump(const Duration(minutes: 1, seconds: 30));
        deliverPosition(tB);
        await tester.pump();
        expect(find.textContaining('현재 위치'), findsOneWidget);

        // A 기준 2분(=B 기준 30초) — 재예약이 B 를 향해 걸렸다면 A 의
        // 예약은 이미 취소된 상태라 이 시점에는 아무것도 전환되지 않는다.
        clock.value = t0.add(const Duration(minutes: 2));
        await tester.pump(const Duration(seconds: 30));
        expect(find.textContaining('현재 위치'), findsOneWidget);
        expect(find.textContaining('마지막 확인 위치'), findsNothing);

        // B 기준 2분 — 재예약이 실제로 B 를 향해 걸렸어야 이 시점에
        // 전환된다. A 의 예약만 살아 있는 결함이면 여기서 전환이
        // 일어나지 않는다(A 의 타이머는 이미 위에서 소진됐다).
        clock.value = tB.add(const Duration(minutes: 2));
        await tester.pump(const Duration(minutes: 1, seconds: 30));
        expect(find.textContaining('마지막 확인 위치 · 2분 전'), findsOneWidget);
        expect(find.textContaining('현재 위치'), findsNothing);
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
}
