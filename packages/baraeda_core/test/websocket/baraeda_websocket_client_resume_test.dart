import 'dart:async';
import 'dart:io';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// `baraeda_websocket_client_lifecycle_test.dart` 와 같은 구조의 가짜 저장소.
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

/// 매 CONNECT 를 정상 CONNECTED 로 받는 가짜 서버 — 연결 횟수를 센다.
class _StompServer {
  int connectCount = 0;
  final List<WebSocket> _sockets = [];
  HttpServer? _server;

  Future<int> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      _sockets.add(socket);
      socket.listen((dynamic data) {
        if (data is String && data.startsWith('CONNECT')) {
          connectCount += 1;
          socket.add('CONNECTED\nversion:1.2\n\n\x00');
        } else if (data is String && data.startsWith('DISCONNECT')) {
          // 실서버처럼 DISCONNECT 에 소켓을 닫는다 — 옛 소켓의 닫힘 신호가
          // 클라이언트에 실제로 도착하는 상황을 만든다.
          unawaited(socket.close());
        }
      });
    });
    return server.port;
  }

  /// 하트비트(빈 줄)를 보낸다 — 서버가 조용하지 않다는 신호.
  void sendHeartbeat() {
    for (final socket in _sockets) {
      if (socket.readyState == WebSocket.open) socket.add('\n');
    }
  }

  Future<void> stop() async {
    for (final socket in _sockets) {
      await socket.close();
    }
    await _server?.close(force: true);
  }
}

/// 시험이 시각을 옮기는 가짜 시계.
class _MutableClock implements Clock {
  new(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

Future<void> _connected(BaraedaWebSocketClient client) => client.connectionState
    .firstWhere((s) => s == WsConnectionState.connected)
    .timeout(const Duration(seconds: 3));

void main() {
  // R46-FIXCONN C-11 — 앱이 백그라운드에서 소켓이 조용히 죽어도 상태는
  // `connected` 로 남는다. `reconnectNow()` 는 재연결 대기·포기 상태에서만
  // 동작해, 죽은 소켓은 하트비트 점검(최대 10초 + 종료 시간)에서야 잡혔다.
  // 복귀 때 마지막 서버 프레임(하트비트 포함)이 20초를 넘었으면 연결이 죽은
  // 것으로 보고 바로 다시 붙인다.
  group('BaraedaWebSocketClient — 복귀 직후 죽은 연결 정리(C-11)', () {
    late _StompServer server;
    late _MutableClock clock;
    late BaraedaWebSocketClient client;

    setUp(() async {
      server = _StompServer();
      clock = _MutableClock(DateTime.utc(2026, 10, 1, 9));
      final port = await server.start();
      client = BaraedaWebSocketClient(
        url: 'ws://127.0.0.1:$port/ws/location',
        tokenStorage: _buildTokenStorage(),
        clock: clock,
      )..connect();
      await _connected(client);
    });

    tearDown(() async {
      client.dispose();
      await server.stop();
    });

    test('마지막 서버 프레임이 20초를 넘었으면 connected 여도 강제로 다시 붙는다', () async {
      expect(server.connectCount, 1);
      clock.value = clock.value.add(const Duration(seconds: 21));

      client.reconnectNow();
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(server.connectCount, 2);
      expect(client.state, WsConnectionState.connected);
    });

    test('강제 재연결 뒤 옛 소켓의 닫힘 신호가 재연결을 또 걸지 않는다', () async {
      clock.value = clock.value.add(const Duration(seconds: 21));

      client.reconnectNow();
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      expect(server.connectCount, 2);
      expect(client.state, WsConnectionState.connected);
    });

    test('하트비트가 오면 마지막 서버 프레임 시각이 갱신돼 연결을 건드리지 않는다', () async {
      // 연결 시각으로부터는 25초 — 하지만 15초 지점에 하트비트가 왔으니 마지막 프레임은 10초 전이다.
      clock.value = clock.value.add(const Duration(seconds: 15));
      server.sendHeartbeat();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      clock.value = clock.value.add(const Duration(seconds: 10));

      client.reconnectNow();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(server.connectCount, 1);
      expect(client.state, WsConnectionState.connected);
    });

    test('마지막 서버 프레임이 20초 안이면 연결을 건드리지 않는다', () async {
      clock.value = clock.value.add(const Duration(seconds: 19));

      client.reconnectNow();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(server.connectCount, 1);
      expect(client.state, WsConnectionState.connected);
    });

    test('일부러 끊은(disconnect) 연결은 오래됐어도 되살리지 않는다', () async {
      client.disconnect();
      clock.value = clock.value.add(const Duration(minutes: 5));

      client.reconnectNow();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(server.connectCount, 1);
      expect(client.state, WsConnectionState.disconnected);
    });
  });
}
