import 'dart:math';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

// 재접속 무작위 폭 · 하트비트 · ERROR `UNAUTHORIZED` · 종료 코드 4500·1008.
// 소켓 없이 STOMP 클라이언트를 가짜로 바꿔 `fake_async` 로 시간을 돌린다.

/// `nextDouble()` 을 고정값으로 돌려주는 난수.
class _FixedRandom implements Random {
  new(this.value);

  final double value;

  @override
  double nextDouble() => value;

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  int nextInt(int max) => throw UnimplementedError();
}

/// 저장소 없이 접근 토큰만 돌려주는 가짜.
class _FakeTokenStorage implements TokenStorage {
  @override
  Future<String?> readAccessToken() async => 'old-token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 소켓을 열지 않는 STOMP 클라이언트 — 시험이 설정 콜백을 직접 부른다.
class _FakeStomp extends StompClient {
  new(StompConfig config) : super(config: config);

  bool isConnected = false;

  @override
  bool get connected => isConnected;

  @override
  void activate() {}

  @override
  void deactivate() {
    isConnected = false;
  }

  @override
  StompUnsubscribe subscribe({
    required String destination,
    required StompFrameCallback callback,
    Map<String, String>? headers,
  }) => ({unsubscribeHeaders}) {};

  /// 서버가 CONNECTED 를 줬다.
  void serverConnected() {
    isConnected = true;
    config.onConnect(StompFrame(command: 'CONNECTED'));
  }

  /// 서버가 `ERROR` 프레임을 보냈다.
  void serverError(String message) => config.onStompError(
    StompFrame(command: 'ERROR', headers: {'message': message}),
  );

  /// 서버가 종료 코드와 함께 소켓을 닫았다 — `stomp_dart_client` 는 코드를 디버그 메시지로만 알린다.
  void serverClosed(int code) {
    config.onDebugMessage(
      'Server closed the connection with code: $code and reason: test',
    );
    isConnected = false;
    config.onWebSocketDone();
  }

  String? get authorization => config.stompConnectHeaders?['Authorization'];
}

class _Harness {
  new({
    Random? random,
    this.refreshResults = const [],
    this.refreshThrows = false,
  }) {
    client = BaraedaWebSocketClient(
      url: 'ws://test/ws/location',
      tokenStorage: _FakeTokenStorage(),
      random: random ?? _FixedRandom(0.999),
      refreshAccessToken: () async {
        refreshCalls += 1;
        if (refreshThrows) throw StateError('network');
        return refreshResults.isEmpty
            ? null
            : refreshResults[min(refreshCalls, refreshResults.length) - 1];
      },
      stompClientFactory: (config) {
        final stomp = _FakeStomp(config);
        stomps.add(stomp);
        return stomp;
      },
    );
    client.sessionExpired.listen((_) => sessionExpiredCount += 1);
  }

  late final BaraedaWebSocketClient client;
  final List<_FakeStomp> stomps = [];
  final List<String?> refreshResults;
  final bool refreshThrows;
  int refreshCalls = 0;
  int sessionExpiredCount = 0;
}

void main() {
  test('하트비트는 보내는 쪽 · 받는 쪽 모두 10초로 명시한다', () {
    fakeAsync((async) {
      final h = _Harness()..client.connect();
      async.flushMicrotasks();

      final config = h.stomps.single.config;
      expect(config.heartbeatOutgoing, const Duration(seconds: 10));
      expect(config.heartbeatIncoming, const Duration(seconds: 10));
      h.client.dispose();
    });
  });

  group('재접속 대기 — 무작위 폭은 [0, 기준값]', () {
    test('난수가 0 이면 대기 없이 바로 다시 붙는다', () {
      fakeAsync((async) {
        final h = _Harness(random: _FixedRandom(0))..client.connect();
        async.flushMicrotasks();
        h.stomps.single.serverClosed(1006);
        expect(h.client.state, WsConnectionState.reconnecting);

        async.elapse(const Duration(milliseconds: 1));

        expect(h.stomps, hasLength(2));
        h.client.dispose();
      });
    });

    test('난수가 끝값이면 기준값(1초)을 넘기지 않고 그 직전에 붙는다', () {
      fakeAsync((async) {
        final h = _Harness()..client.connect();
        async.flushMicrotasks();
        h.stomps.single.serverClosed(1006);

        async.elapse(const Duration(milliseconds: 990));
        expect(h.stomps, hasLength(1));

        async.elapse(const Duration(milliseconds: 10));
        expect(h.stomps, hasLength(2));
        h.client.dispose();
      });
    });
  });

  group('ERROR UNAUTHORIZED', () {
    test('재발급을 한 번 하고 새 토큰으로 다시 붙는다', () {
      fakeAsync((async) {
        final h = _Harness(refreshResults: ['new-token'])..client.connect();
        async.flushMicrotasks();
        h.stomps.single
          ..serverError('UNAUTHORIZED')
          ..serverClosed(1008);
        async.flushMicrotasks();

        expect(h.refreshCalls, 1);
        expect(h.stomps, hasLength(2));
        expect(h.stomps.last.authorization, 'Bearer new-token');
        expect(h.sessionExpiredCount, 0);
        h.client.dispose();
      });
    });

    test('재발급이 실패하면 세션 만료로 넘기고 30초 재시도를 하지 않는다', () {
      fakeAsync((async) {
        final h = _Harness()..client.connect();
        async.flushMicrotasks();
        h.stomps.single
          ..serverError('UNAUTHORIZED')
          ..serverClosed(1008);
        async.flushMicrotasks();

        expect(h.sessionExpiredCount, 1);
        expect(h.client.state, WsConnectionState.disconnected);

        async.elapse(const Duration(seconds: 120));
        expect(h.stomps, hasLength(1));
        expect(h.refreshCalls, 1);
        h.client.dispose();
      });
    });

    test('재발급한 새 토큰도 UNAUTHORIZED 면 세션 만료 — 재발급을 되풀이하지 않는다', () {
      fakeAsync((async) {
        final h = _Harness(refreshResults: ['new-token'])..client.connect();
        async.flushMicrotasks();
        h.stomps.single
          ..serverError('UNAUTHORIZED')
          ..serverClosed(1008);
        async.flushMicrotasks();
        h.stomps.last
          ..serverError('UNAUTHORIZED')
          ..serverClosed(1008);
        async.flushMicrotasks();

        expect(h.refreshCalls, 1);
        expect(h.sessionExpiredCount, 1);
        async.elapse(const Duration(seconds: 120));
        expect(h.stomps, hasLength(2));
        h.client.dispose();
      });
    });

    // Ruling 905 — 재발급이 일시 장애(네트워크 · 5xx · 시간 초과)로 던지면 자격이 거절된 것이 아니다.
    // 세션을 만료시키지 않고 일반 백오프로 계속 다시 붙는다.
    test('재발급이 일시 장애로 던지면 세션을 만료시키지 않고 백오프로 다시 붙는다 (Ruling 905)', () {
      fakeAsync((async) {
        final h = _Harness(refreshThrows: true)..client.connect();
        async.flushMicrotasks();
        h.stomps.single
          ..serverError('UNAUTHORIZED')
          ..serverClosed(1008);
        async.flushMicrotasks();

        expect(h.refreshCalls, 1);
        expect(h.sessionExpiredCount, 0);
        expect(h.client.state, WsConnectionState.reconnecting);

        async.elapse(const Duration(seconds: 1));
        expect(h.stomps, hasLength(2), reason: '백오프 첫 단계(≤ 1초) 안에 다시 붙는다');
        h.client.dispose();
      });
    });

    // 재발급 1회 표식은 CONNECTED 를 못 받은 채 수동으로 끊고 다시 연결해도 새로 시작한다.
    test('CONNECTED 전 disconnect → connect 해도 재발급 1회를 다시 얻는다', () {
      fakeAsync((async) {
        final h = _Harness(refreshResults: ['t1', 't2'])..client.connect();
        async.flushMicrotasks();
        h.stomps.single
          ..serverError('UNAUTHORIZED')
          ..serverClosed(1008);
        async.flushMicrotasks();
        expect(h.refreshCalls, 1);

        h.client
          ..disconnect()
          ..connect();
        async.flushMicrotasks();
        h.stomps.last
          ..serverError('UNAUTHORIZED')
          ..serverClosed(1008);
        async.flushMicrotasks();

        expect(h.refreshCalls, 2);
        expect(h.sessionExpiredCount, 0);
        expect(h.stomps.last.authorization, 'Bearer t2');
        h.client.dispose();
      });
    });

    test('재발급 뒤 연결에 성공하면 다음 UNAUTHORIZED 는 다시 재발급 한 번을 얻는다', () {
      fakeAsync((async) {
        final h = _Harness(refreshResults: ['t1', 't2'])..client.connect();
        async.flushMicrotasks();
        h.stomps.single
          ..serverError('UNAUTHORIZED')
          ..serverClosed(1008);
        async.flushMicrotasks();
        h.stomps.last
          ..serverConnected()
          ..serverError('UNAUTHORIZED')
          ..serverClosed(1008);
        async.flushMicrotasks();

        expect(h.refreshCalls, 2);
        expect(h.stomps.last.authorization, 'Bearer t2');
        expect(h.sessionExpiredCount, 0);
        h.client.dispose();
      });
    });
  });

  group('종료 코드', () {
    test('4500 은 앞선 실패 횟수와 무관하게 첫 단계(1초) 안에 다시 붙는다', () {
      fakeAsync((async) {
        final h = _Harness()..client.connect();
        async.flushMicrotasks();
        // CONNECTED 를 못 받고 세 번 끊긴다 — 일반 경로면 다음 대기는 8초 단계다.
        for (var i = 0; i < 3; i++) {
          h.stomps.last.serverClosed(1006);
          async.elapse(Duration(seconds: 1 << i));
        }
        expect(h.stomps, hasLength(4));

        h.stomps.last.serverClosed(4500);
        async.elapse(const Duration(seconds: 1));

        expect(h.stomps, hasLength(5));
        h.client.dispose();
      });
    });

    test('1008 은 일반 백오프를 탄다 — 두 번째 실패의 대기는 첫 단계를 넘는다', () {
      fakeAsync((async) {
        final h = _Harness()..client.connect();
        async.flushMicrotasks();
        h.stomps.last.serverClosed(1008);
        async.elapse(const Duration(seconds: 1));
        expect(h.stomps, hasLength(2));

        h.stomps.last.serverClosed(1008);
        async.elapse(const Duration(seconds: 1));
        expect(h.stomps, hasLength(2));

        async.elapse(const Duration(seconds: 1));
        expect(h.stomps, hasLength(3));
        h.client.dispose();
      });
    });
  });
}
