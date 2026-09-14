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
    Future<void> pumpConnected(WidgetTester tester) async {
      await pumpScreen(
        tester,
        extraOverrides: [
          roleCapabilitiesProvider.overrideWithValue(
            RoleCapabilities.of(UserRole.student),
          ),
          myStudentIdProvider.overrideWith((ref) async => 's-1'),
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
}
