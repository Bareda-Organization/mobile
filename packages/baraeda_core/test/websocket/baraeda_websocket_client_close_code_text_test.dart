import 'dart:async';
import 'dart:io';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// 4500 빠른 재접속은 `stomp_dart_client` 가 종료 코드를 디버그 문구로만 알리는 데 기댄다.
// 실제 소켓으로 그 문구가 그대로인지 고정한다 — 라이브러리를 올려 문구가 바뀌면 여기서 먼저 실패한다.
class _FakeSecureStoragePlatform
    with MockPlatformInterfaceMixin
    implements FlutterSecureStoragePlatform {
  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => null;

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {}

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {}

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => false;

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => {};

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {}

  @override
  Future<SecureStorageUpgradeStatus> checkUpgradeStatus({
    required Map<String, String> options,
  }) async =>
      const SecureStorageUpgradeStatus(state: SecureStorageUpgradeState.ok);
}

void main() {
  test('서버가 4500 으로 닫으면 디버그 문구에 코드가 실리고 곧바로 다시 붙는다', () async {
    FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
    var connections = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((dynamic data) {
        if (data is! String || !data.startsWith('CONNECT')) return;
        connections += 1;
        socket.add('CONNECTED\nversion:1.2\n\n\x00');
        if (connections == 1) {
          Timer(const Duration(milliseconds: 30), () {
            unawaited(socket.close(4500, 'SESSION_REVOKED'));
          });
        }
      });
    });
    final debug = <String>[];
    final client = BaraedaWebSocketClient(
      url: 'ws://127.0.0.1:${server.port}/ws/location',
      tokenStorage: TokenStorage(
        accessTokenKey: 'access',
        refreshTokenKey: 'refresh',
      ),
      onDebugMessage: debug.add,
    );
    addTearDown(client.dispose);

    client.connect();
    final deadline = DateTime.now().add(const Duration(seconds: 4));
    while (connections < 2 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(
      debug.any(
        (m) => m.startsWith('Server closed the connection with code: 4500'),
      ),
      isTrue,
      reason: 'stomp_dart_client 가 종료 코드를 알리는 문구가 바뀌었다',
    );
    expect(connections, greaterThanOrEqualTo(2));
  });
}
