import 'dart:io';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

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

/// 소켓 연결은 받아 주지만 STOMP CONNECT 에 **끝내 CONNECTED 를 안 주는** 서버 —
/// 서버 인바운드 실행기가 포화되었거나 반쯤 죽은 서버를 흉내 낸다.
class _SilentServer {
  int upgradeCount = 0;
  final List<WebSocket> _sockets = [];
  HttpServer? _server;

  Future<int> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      upgradeCount += 1;
      _sockets.add(socket);
      socket.listen((dynamic _) {});
    });
    return server.port;
  }

  Future<void> stop() async {
    for (final socket in _sockets) {
      await socket.close();
    }
    await _server?.close(force: true);
  }
}

void main() {
  // R46-FIXCONN C-4 — 소켓은 열렸는데 CONNECTED 가 안 오면 한도가 없어
  // `connecting` 에서 영영 막혔다(재연결 타이머는 close·error 뒤에만 예약된다).
  // 한도를 넘기면 시도를 끊고 백오프 재연결로 이어진다.
  group('BaraedaWebSocketClient — 연결 시도 시간 제한(C-4)', () {
    late _SilentServer server;

    setUp(() => server = _SilentServer());
    tearDown(() async => server.stop());

    test(
      'CONNECTED 가 한도 안에 안 오면 연결 시도를 끊고 reconnecting 으로 이어서 다시 시도한다',
      () async {
        final port = await server.start();
        final client = BaraedaWebSocketClient(
          url: 'ws://127.0.0.1:$port/ws/location',
          tokenStorage: _buildTokenStorage(),
          connectTimeout: const Duration(milliseconds: 200),
          backoffPolicy: const WsBackoffPolicy(
            initialDelay: Duration(milliseconds: 20),
            maxDelay: Duration(milliseconds: 40),
            jitterRatio: 0,
          ),
        );
        addTearDown(client.dispose);

        // 한도(200ms)의 몇 배 안에 끊겨야 한다 — 한도가 실제로 쓰이는지 가리는 값.
        final reconnecting = client.connectionState
            .firstWhere((s) => s == WsConnectionState.reconnecting)
            .timeout(const Duration(seconds: 1));
        client.connect();
        await reconnecting;

        // 다음 시도가 실제로 이어진다 — 두 번째 소켓이 서버에 도착한다.
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(server.upgradeCount, greaterThanOrEqualTo(2));
      },
    );

    test('연결이 되면 감시 타이머가 연결을 끊지 않는다', () async {
      // 한도(150ms)보다 오래 연결된 채로 둬도 `connected` 가 유지돼야 한다 —
      // 감시를 정리하지 않으면 정상 연결을 끊는다.
      final connectedServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => connectedServer.close(force: true));
      var connectCount = 0;
      connectedServer.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((dynamic data) {
          if (data is String && data.startsWith('CONNECT')) {
            connectCount += 1;
            socket.add('CONNECTED\nversion:1.2\n\n\x00');
          }
        });
      });
      final client = BaraedaWebSocketClient(
        url: 'ws://127.0.0.1:${connectedServer.port}/ws/location',
        tokenStorage: _buildTokenStorage(),
        connectTimeout: const Duration(milliseconds: 150),
      );
      addTearDown(client.dispose);

      client.connect();
      await client.connectionState
          .firstWhere((s) => s == WsConnectionState.connected)
          .timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(client.state, WsConnectionState.connected);
      expect(connectCount, 1);
    });

    test('WebSocket 핑 주기가 StompConfig 에 실린다', () async {
      // 반쯤 죽은 TCP 는 dart:io 의 핑·퐁이 STOMP 하트비트와 별개로 잡는다 —
      // 설정이 실제로 라이브러리에 닿아야 한다.
      final configs = <StompConfig>[];
      final client = BaraedaWebSocketClient(
        url: 'ws://127.0.0.1:1/ws/location',
        tokenStorage: _buildTokenStorage(),
        stompClientFactory: (config) {
          configs.add(config);
          return StompClient(config: config);
        },
      );
      addTearDown(client.dispose);

      client.connect();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(configs, isNotEmpty);
      expect(configs.first.pingInterval, const Duration(seconds: 10));
    });

    test('소켓 핸드셰이크가 끝내 안 끝나는 서버도 한도 안에 끊고 다시 시도한다', () async {
      // TCP 는 받지만 WebSocket 업그레이드에 응답하지 않는다 — 인터넷 없는
      // Wi-Fi·포획 포털처럼 소켓 열기 단계에서 막히는 상황.
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(raw.close);
      final accepted = <Socket>[];
      raw.listen(accepted.add);
      final client = BaraedaWebSocketClient(
        url: 'ws://127.0.0.1:${raw.port}/ws/location',
        tokenStorage: _buildTokenStorage(),
        connectTimeout: const Duration(milliseconds: 200),
        backoffPolicy: const WsBackoffPolicy(
          initialDelay: Duration(milliseconds: 20),
          maxDelay: Duration(milliseconds: 40),
          jitterRatio: 0,
        ),
      );
      addTearDown(client.dispose);

      final reconnecting = client.connectionState
          .firstWhere((s) => s == WsConnectionState.reconnecting)
          .timeout(const Duration(seconds: 1));
      client.connect();
      await reconnecting;

      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(accepted.length, greaterThanOrEqualTo(2));
    });
  });
}
