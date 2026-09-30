import 'dart:async';
import 'dart:io';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// `baraeda_websocket_client_reconnect_test.dart` 와 같은 구조의 가짜.
class _FakeSecureStoragePlatform
    with MockPlatformInterfaceMixin
    implements FlutterSecureStoragePlatform {
  final Map<String, String> data = {};

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => data[key];

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    data[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    data.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => data.containsKey(key);

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map.of(data);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    data.clear();
  }

  @override
  Future<SecureStorageUpgradeStatus> checkUpgradeStatus({
    required Map<String, String> options,
  }) async => const SecureStorageUpgradeStatus(
    state: SecureStorageUpgradeState.ok,
  );
}

TokenStorage _buildTokenStorage() {
  FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
  return TokenStorage(accessTokenKey: 'access', refreshTokenKey: 'refresh');
}

/// 매 CONNECT 를 정상 CONNECTED 로 받고, SUBSCRIBE 가 오면 시험이 MESSAGE 를 밀어 넣을 수 있는
/// 가짜 서버. `expireFirstConnection` 이면 첫 연결만 잠시 뒤 `ERROR TOKEN_EXPIRED` 로 닫는다.
class _StompServer {
  _StompServer({this.expireFirstConnection = false});

  final bool expireFirstConnection;
  int connectCount = 0;
  final List<WebSocket> _sockets = [];
  final List<String> _subscriptionIds = [];
  HttpServer? _server;

  Future<int> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      _sockets.add(socket);
      socket.listen((dynamic data) {
        final text = data is String ? data : '';
        if (text.startsWith('CONNECT')) {
          connectCount += 1;
          socket.add('CONNECTED\nversion:1.2\n\n\x00');
          if (expireFirstConnection && connectCount == 1) {
            Timer(const Duration(milliseconds: 20), () {
              socket.add(
                'ERROR\nmessage:TOKEN_EXPIRED\ncontent-length:0\n\n\x00',
              );
              unawaited(socket.close());
            });
          }
        } else if (text.startsWith('SUBSCRIBE')) {
          final id = RegExp(r'id:(\S+)').firstMatch(text)?.group(1);
          if (id != null) _subscriptionIds.add(id);
        }
      });
    });
    return server.port;
  }

  /// 구독자에게 MESSAGE 프레임 하나를 보낸다 — `content-type` 이 없으면 stomp_dart_client 가
  /// 본문을 바이너리로 취급해 `frame.body` 가 null 이 된다(실서버는 application/json 을 붙인다).
  void push(String body) {
    _sockets.first.add(
      'MESSAGE\nsubscription:${_subscriptionIds.first}\ndestination:/topic/x\n'
      'message-id:1\ncontent-type:application/json\n\n$body\x00',
    );
  }

  Future<void> stop() async {
    for (final socket in _sockets) {
      await socket.close();
    }
    await _server?.close(force: true);
  }
}

Future<void> _connected(BaraedaWebSocketClient client) => client.connectionState
    .firstWhere((s) => s == WsConnectionState.connected)
    .timeout(const Duration(seconds: 5));

void main() {
  group('BaraedaWebSocketClient — 수명주기(F07-03·04·08)', () {
    late _StompServer server;

    tearDown(() async {
      await server.stop();
    });

    test('연결 중·연결됨에 connect() 를 또 불러도 소켓을 하나 더 열지 않는다', () async {
      // F07-04 — 예전엔 `_stompClient` 를 정리 없이 덮어써 소켓이 누수됐다.
      server = _StompServer();
      final port = await server.start();
      final client = BaraedaWebSocketClient(
        url: 'ws://127.0.0.1:$port/ws/location',
        tokenStorage: _buildTokenStorage(),
      );
      addTearDown(client.dispose);

      client
        ..connect()
        ..connect(); // 첫 호출이 아직 connecting 일 때
      await _connected(client);
      client.connect(); // 이미 connected
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(server.connectCount, 1);
      expect(client.state, WsConnectionState.connected);
    });

    test('재발급을 기다리는 사이 disconnect() 하면 재발급이 끝나도 소켓을 되살리지 않는다', () async {
      // F07-03 — 로그아웃 뒤 실시간 방송이 계속 들어오던 경로.
      server = _StompServer(expireFirstConnection: true);
      final port = await server.start();
      final refreshGate = Completer<String?>();
      final client = BaraedaWebSocketClient(
        url: 'ws://127.0.0.1:$port/ws/location',
        tokenStorage: _buildTokenStorage(),
        refreshAccessToken: () => refreshGate.future,
      );
      addTearDown(client.dispose);

      client.connect();
      await _connected(client);
      // TOKEN_EXPIRED 로 끊겨 재발급 대기(reconnecting)에 들어갈 때까지.
      await client.connectionState
          .firstWhere((s) => s == WsConnectionState.reconnecting)
          .timeout(const Duration(seconds: 5));

      client.disconnect(); // 사용자가 로그아웃
      refreshGate.complete('late-token');
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(server.connectCount, 1);
      expect(client.state, WsConnectionState.disconnected);
    });

    test('재발급 요청이 일시 장애로 실패하면 sessionExpired 가 아니라 백오프로 재연결한다', () async {
      // F07-02 의 WS 쪽 — 재발급이 네트워크 오류로 던지면 세션 종료로 오인하지 않는다.
      server = _StompServer(expireFirstConnection: true);
      final port = await server.start();
      var refreshCalls = 0;
      final client = BaraedaWebSocketClient(
        url: 'ws://127.0.0.1:$port/ws/location',
        tokenStorage: _buildTokenStorage(),
        backoffPolicy: const WsBackoffPolicy(
          initialDelay: Duration(milliseconds: 20),
          maxDelay: Duration(milliseconds: 40),
        ),
        refreshAccessToken: () async {
          refreshCalls += 1;
          throw DioException.connectionError(
            requestOptions: RequestOptions(path: '/auth/refresh'),
            reason: '끊김',
          );
        },
      );
      addTearDown(client.dispose);
      var sessionExpiredCount = 0;
      final sub = client.sessionExpired.listen((_) => sessionExpiredCount += 1);
      addTearDown(sub.cancel);

      client.connect();
      await _connected(client);
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(sessionExpiredCount, 0);
      expect(refreshCalls, greaterThanOrEqualTo(1));
      expect(server.connectCount, greaterThanOrEqualTo(2));
    });

    test('payload 가 없거나 깨진 프레임은 그 프레임만 버리고 구독은 계속 산다', () async {
      // F07-08 — 예전엔 `null as Map` TypeError 가 STOMP 콜백 밖으로 새 처리되지 않은
      // 오류가 됐고, 이벤트가 안 오는 것으로만 보였다.
      server = _StompServer();
      final port = await server.start();
      final debug = <String>[];
      final client = BaraedaWebSocketClient(
        url: 'ws://127.0.0.1:$port/ws/location',
        tokenStorage: _buildTokenStorage(),
        onDebugMessage: debug.add,
      );
      addTearDown(client.dispose);
      client.connect();
      await _connected(client);

      final received = <WebSocketEnvelope>[];
      client.subscribe('/topic/x', received.add);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      const at = '"occurred_at":"2026-09-30T10:00:00Z"';
      server
        ..push('not json') // FormatException
        ..push('[1,2]') // JSON 이지만 Map 이 아니다 — TypeError
        ..push('{"event":"route_changed","run_id":1,$at}')
        ..push('{"event":"run_started","run_id":1,$at,"payload":{}}');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(received.map((e) => e.eventWireValue), [
        'route_changed',
        'run_started',
      ]);
      expect(received.first.payload, isEmpty);
      expect(debug.where((m) => m.contains('프레임 파싱 실패')), hasLength(2));
    });

    test('connect() 직후 disconnect() 하면 토큰을 읽고 돌아와도 소켓을 열지 않는다', () async {
      // F07-03(b) — `_doConnect` 안 저장소 읽기 `await` 뒤의 좁은 틈.
      server = _StompServer();
      final port = await server.start();
      final client = BaraedaWebSocketClient(
        url: 'ws://127.0.0.1:$port/ws/location',
        tokenStorage: _buildTokenStorage(),
      );
      addTearDown(client.dispose);

      client
        ..connect()
        ..disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(server.connectCount, 0);
      expect(client.state, WsConnectionState.disconnected);
    });
  });
}
