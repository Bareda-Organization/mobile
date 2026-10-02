import 'dart:async';
import 'dart:typed_data';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/features/live_map/domain/bus_position.dart';
import 'package:parent_app/features/live_map/domain/bus_position_repository.dart';
import 'package:parent_app/features/live_map/presentation/live_map_providers.dart';
// `Override` 는 `flutter_riverpod` 배럴이 재노출하지 않는다
// (`live_map_screen_test.dart` 와 같은 사정).
import 'package:riverpod/misc.dart' show Override;

import '../../support/fake_token_storage.dart';

/// R46-FIXCONN C-2 — 실시간 연결은 앱 전역 하나라 로그아웃·지도 화면 이탈
/// 뒤에도 옛 계정의 토큰으로 살아 있었다. 같은 단말에서 계정을 바꿔 지도를
/// 열면 `connected` 라 새 연결을 안 열고 **옛 계정 권한으로 구독**해, 자녀가
/// 다른 학부모에게는 *"조회 권한 없음"* 이 떴다(서버는 연결 시점의 인증
/// 주체로 판정한다). 소켓 없이 "연결을 닫는가 · 새 계정이 새 연결을 여는가"
/// 만 보는 가짜 클라이언트.
class _LifetimeWsClient extends BaraedaWebSocketClient {
  new()
    : super(
        url: 'ws://test.invalid/ws/location',
        tokenStorage: TokenStorage(
          accessTokenKey: 'ws-lifetime-access',
          refreshTokenKey: 'ws-lifetime-refresh',
        ),
      );

  final _stateController = StreamController<WsConnectionState>.broadcast();
  final _sessionExpiredController = StreamController<void>.broadcast();
  WsConnectionState _fakeState = WsConnectionState.connected;
  int connectCalls = 0;
  int disconnectCalls = 0;
  final List<String> subscribed = [];

  @override
  WsConnectionState get state => _fakeState;

  @override
  Stream<WsConnectionState> get connectionState => _stateController.stream;

  @override
  Stream<String> get forbiddenSubscriptions => const Stream<String>.empty();

  @override
  Stream<void> get sessionExpired => _sessionExpiredController.stream;

  void emit(WsConnectionState next) {
    _fakeState = next;
    _stateController.add(next);
  }

  void emitSessionExpired() => _sessionExpiredController.add(null);

  @override
  void connect() {
    connectCalls++;
    emit(WsConnectionState.connecting);
  }

  @override
  void disconnect() {
    disconnectCalls++;
    subscribed.clear(); // 소켓이 닫히면 그 위의 구독도 사라진다.
    emit(WsConnectionState.disconnected);
  }

  @override
  void Function({Map<String, String>? unsubscribeHeaders}) subscribe(
    String destination,
    void Function(WebSocketEnvelope) onEnvelope,
  ) {
    subscribed.add(destination);
    return ({Map<String, String>? unsubscribeHeaders}) =>
        subscribed.remove(destination);
  }

  @override
  void dispose() {
    unawaited(_stateController.close());
    unawaited(_sessionExpiredController.close());
  }
}

/// §3.11 스냅샷은 이 시험의 관심사가 아니다 — 네트워크를 건드리지 않고 즉시 실패시킨다.
class _FailingBusPositionRepository implements BusPositionRepository {
  @override
  Future<BusPosition> getBusPosition(String studentId) =>
      Future.error(const Failure.unknown(message: 'test fake — no REST'));
}

class _StubAuthRepository implements AuthRepository {
  @override
  Future<void> logout() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 재발급 요청에 `401` 을 돌려주는 어댑터 — refresh 토큰이 거절된 상황.
class _RejectRefreshAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{"error":{"code":"TOKEN_EXPIRED","message":"m"}}',
    401,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  late _LifetimeWsClient wsClient;

  ProviderContainer makeContainer({List<Override> extra = const []}) {
    final container = ProviderContainer(
      overrides: [
        webSocketClientProvider.overrideWithValue(wsClient),
        busPositionRepositoryProvider.overrideWithValue(
          _FailingBusPositionRepository(),
        ),
        authRepositoryProvider.overrideWithValue(_StubAuthRepository()),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() => wsClient = _LifetimeWsClient());

  group('연결 수명 — 지도 화면에 묶는다', () {
    test('지도를 열고 있는 동안은 연결을 유지하고, 마지막 지도가 닫히면 연결을 끊는다', () async {
      final container = makeContainer();
      final first = container.listen(liveMapStateProvider('s-1'), (_, _) {});
      final second = container.listen(liveMapStateProvider('s-2'), (_, _) {});
      await pumpEventQueue();

      first.close(); // 자녀를 전환해 하나만 남았다 — 연결은 그대로여야 한다.
      await pumpEventQueue();
      expect(wsClient.disconnectCalls, 0);

      second.close(); // 지도 화면을 떠났다.
      await pumpEventQueue();
      expect(wsClient.disconnectCalls, 1);
    });
  });

  group('로그아웃·세션 만료 — 연결을 끊는다', () {
    testWidgets('로그아웃하면 공용 연결을 끊는다', (tester) async {
      late WidgetRef ref;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webSocketClientProvider.overrideWithValue(wsClient),
            authRepositoryProvider.overrideWithValue(_StubAuthRepository()),
          ],
          child: Consumer(
            builder: (context, r, _) {
              ref = r;
              return const SizedBox();
            },
          ),
        ),
      );

      await signOut(ref);

      expect(wsClient.disconnectCalls, 1);
    });

    test('REST 재발급이 거절돼 로그인이 풀려도 공용 연결을 끊는다', () async {
      final tokens = FakeTokenStorage(
        seedRefreshToken: 'r',
        seedAccessToken: 'a',
      );
      final container = makeContainer(
        extra: [
          tokenStorageProvider.overrideWithValue(tokens),
          apiClientProvider.overrideWith(
            (ref) => ApiClient(
              tokenStorage: tokens,
              baseUrl: 'https://example.invalid',
              refreshDio: Dio(BaseOptions(baseUrl: 'https://example.invalid'))
                ..httpClientAdapter = _RejectRefreshAdapter(),
            ),
          ),
        ],
      );
      container.read(currentUserRoleProvider.notifier).state = UserRole.parent;
      container.read(routerRefreshNotifierProvider);

      await container.read(apiClientProvider).tokenRefresher.refresh();
      await pumpEventQueue();

      expect(wsClient.disconnectCalls, 1);
    });

    test('계정 A → B 전환 — B 의 지도는 A 의 연결을 물려받지 않고 새 연결이 붙은 뒤에 구독한다', () async {
      final container = makeContainer();
      container.read(currentUserRoleProvider.notifier).state = UserRole.parent;
      container.read(routerRefreshNotifierProvider);

      // A 가 지도를 열어 자기 자녀 채널을 구독했다.
      final mapOfA = container.listen(
        liveMapStateProvider('child-of-a'),
        (
          _,
          _,
        ) {},
      );
      await pumpEventQueue();
      expect(wsClient.subscribed, ['/topic/students/child-of-a/run']);

      // 로그아웃(세션 만료) — 연결이 닫힌다. 화면이 사라지며 지도도 닫힌다.
      wsClient.emitSessionExpired();
      await pumpEventQueue();
      mapOfA.close();
      await pumpEventQueue();
      expect(wsClient.state, WsConnectionState.disconnected);

      // B 가 같은 단말에서 로그인해 지도를 연다 — 옛 연결에 구독을 얹으면 안 되고 새 연결을 연다.
      container.listen(liveMapStateProvider('child-of-b'), (_, _) {});
      await pumpEventQueue();
      expect(wsClient.subscribed, isEmpty);
      expect(wsClient.connectCalls, 1);

      // 새 연결이 붙으면(B 의 토큰) 그제서야 B 의 채널을 구독한다.
      wsClient.emit(WsConnectionState.connected);
      await pumpEventQueue();
      expect(wsClient.subscribed, ['/topic/students/child-of-b/run']);
    });
  });
}
