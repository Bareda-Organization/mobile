import 'dart:async';
import 'dart:io';

import 'package:baraeda_core/baraeda_core.dart';
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

/// CONNECT 프레임 텍스트에서 `Authorization` 헤더 값만 뽑아낸다.
String? _authHeaderOf(String connectFrameText) {
  for (final line in connectFrameText.split('\n')) {
    if (line.startsWith('Authorization:')) {
      return line.substring('Authorization:'.length);
    }
  }
  return null;
}

/// 첫 CONNECT 는 받아 준 뒤 `ERROR message:TOKEN_EXPIRED` 를 보내고 세션을
/// 닫는 가짜 서버 — `API_SPEC §7` "세션은 연결한 access 토큰보다 오래 살지
/// 않는다" 를 흉내 낸다. 두 번째부터의 CONNECT 는 정상 CONNECTED 로 받는다.
/// 매 CONNECT 프레임의 `Authorization` 헤더를 기록해 재연결이 실제로 새
/// 토큰을 실었는지 검증하는 데 쓴다.
class _TokenExpiringStompServer {
  int connectCount = 0;
  final List<String?> connectAuthHeaders = [];
  HttpServer? _server;
  final List<WebSocket> _sockets = [];

  Future<int> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      _sockets.add(socket);
      socket.listen((dynamic data) {
        final text = data is String ? data : '';
        if (!text.startsWith('CONNECT')) return;
        connectCount += 1;
        connectAuthHeaders.add(_authHeaderOf(text));
        if (connectCount == 1) {
          socket.add('CONNECTED\nversion:1.2\n\n\x00');
          Timer(const Duration(milliseconds: 20), () {
            socket.add(
              'ERROR\nmessage:TOKEN_EXPIRED\ncontent-length:0\n\n\x00',
            );
            unawaited(socket.close());
          });
        } else {
          socket.add('CONNECTED\nversion:1.2\n\n\x00');
        }
      });
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
  group('BaraedaWebSocketClient — TOKEN_EXPIRED(완료 조건 9)', () {
    late _TokenExpiringStompServer server;

    tearDown(() async {
      await server.stop();
    });

    test(
      'ERROR TOKEN_EXPIRED 를 받으면 재발급 콜백을 먼저 부르고 '
      '새 토큰으로 재연결한다',
      () async {
        server = _TokenExpiringStompServer();
        final port = await server.start();

        final tokenStorage = _buildTokenStorage();
        await tokenStorage.saveTokens(
          accessToken: 'old-token',
          refreshToken: 'r1',
        );

        var refreshCalls = 0;
        final client = BaraedaWebSocketClient(
          url: 'ws://127.0.0.1:$port/ws/location',
          tokenStorage: tokenStorage,
          refreshAccessToken: () async {
            refreshCalls += 1;
            return 'refreshed-token';
          },
        );
        addTearDown(client.dispose);

        final states = <WsConnectionState>[];
        final sub = client.connectionState.listen(states.add);
        addTearDown(sub.cancel);

        client.connect();

        // 1) 첫 CONNECT 로 connected 에 도달한다.
        await client.connectionState
            .firstWhere((s) => s == WsConnectionState.connected)
            .timeout(const Duration(seconds: 5));

        // 2) 서버가 TOKEN_EXPIRED 로 세션을 닫으면 재발급을 거쳐 다시
        //    connected 로 돌아온다. 이 구독은 위 firstWhere 가 끝난 **뒤에**
        //    새로 여는 것이라(broadcast 스트림은 과거를 다시 보내지 않는다)
        //    `skip(1)` 없이 바로 다음 connected 를 기다리면 된다.
        await client.connectionState
            .firstWhere((s) => s == WsConnectionState.connected)
            .timeout(const Duration(seconds: 5));

        expect(refreshCalls, 1);
        expect(server.connectCount, 2);
        expect(server.connectAuthHeaders[0], 'Bearer old-token');
        expect(
          server.connectAuthHeaders[1],
          'Bearer refreshed-token',
          reason: '재연결이 새로 읽은 토큰이 아니라 만료된 옛 토큰을 그대로 '
              '실었다면 여기서 실패한다 — 지금 코드가 바로 이 결함이다.',
        );
        // gaveUp 을 거치지 않고 바로 되살아났다 — 토큰 만료는 네트워크
        // 실패가 아니므로 백오프 상태를 거치지 않는다는 판단(보고서 §2).
        expect(states, isNot(contains(WsConnectionState.gaveUp)));
      },
    );

    test(
      '재발급이 실패하면(refresh 만료 등) gaveUp 이 아니라 '
      'sessionExpired 로 알리고, 더는 재시도하지 않는다',
      () async {
        server = _TokenExpiringStompServer();
        final port = await server.start();

        final client = BaraedaWebSocketClient(
          url: 'ws://127.0.0.1:$port/ws/location',
          tokenStorage: _buildTokenStorage(),
          refreshAccessToken: () async => null,
        );
        addTearDown(client.dispose);

        var sessionExpiredCount = 0;
        final sessionExpiredSub = client.sessionExpired.listen((_) {
          sessionExpiredCount += 1;
        });
        addTearDown(sessionExpiredSub.cancel);

        client.connect();

        await client.connectionState
            .firstWhere((s) => s == WsConnectionState.connected)
            .timeout(const Duration(seconds: 5));

        await client.connectionState
            .firstWhere((s) => s == WsConnectionState.disconnected)
            .timeout(const Duration(seconds: 5));

        expect(sessionExpiredCount, 1);
        expect(client.state, WsConnectionState.disconnected);

        // 더 기다려도 재연결을 시도하지 않는다 — connectCount 가 1(최초
        // 연결)에서 늘지 않는다.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(server.connectCount, 1);
      },
    );
  });
}
