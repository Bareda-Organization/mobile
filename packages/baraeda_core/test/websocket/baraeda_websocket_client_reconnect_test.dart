import 'dart:async';
import 'dart:io';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// `test/integration/real_backend_auth_test.dart` 와 같은 구조의 가짜 —
// TokenStorage 는 실 시크릿 스토리지 플러그인이 필요해서 이 클라이언트를
// 단독으로 시험하려면 매번 같이 있어야 한다.
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

/// 실제 STOMP 규약을 흉내 내는 최소 가짜 WS 서버 — 진짜 스프링 서버를
/// 내렸다 올리는 대신, "몇 번째 연결 시도부터 받아 줄지"를 직접 제어해
/// 재연결 스케줄링을 초 단위가 아니라 밀리초 단위로 검사할 수 있게 한다
/// (`API_SPEC §7` 은 아니지만 완료 조건 3번이 요구하는 것은 클라이언트의
/// 재연결 동작이지 서버 프로토콜 정합성이 아니다 — CONNECTED 최소 프레임만
/// 흉내 내면 충분하다).
class _FlakyStompServer {
  new(this._acceptFromAttempt);

  /// 몇 번째(1부터) 연결 시도부터 업그레이드를 받아 줄지. `null` 이면
  /// 영원히 안 받아 준다("서버가 계속 꺼져 있다").
  final int? _acceptFromAttempt;

  int attempts = 0;
  HttpServer? _server;
  final List<WebSocket> _sockets = [];

  Future<int> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) async {
      attempts += 1;
      final accept =
          _acceptFromAttempt != null && attempts >= _acceptFromAttempt;
      if (!accept) {
        // 서버가 꺼져 있는 상태를 흉내 — 업그레이드를 거부해 클라이언트
        // 쪽 `WebSocket.connect` 가 예외를 던지게 한다.
        request.response.statusCode = HttpStatus.serviceUnavailable;
        unawaited(request.response.close());
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      _sockets.add(socket);
      socket.listen((dynamic data) {
        final text = data is String ? data : '';
        if (text.startsWith('CONNECT')) {
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
  group('BaraedaWebSocketClient — 재연결(완료 조건 3)', () {
    late _FlakyStompServer server;

    tearDown(() async {
      await server.stop();
    });

    test('연결이 실패하는 동안 백오프를 두고 재시도하다 서버가 받아주면 '
        '붙는다', () async {
      // 1·2번째 시도는 거부, 3번째부터 받아준다 — "서버를 내렸다 올린다"의
      // 축소판.
      server = _FlakyStompServer(3);
      final port = await server.start();

      final client = BaraedaWebSocketClient(
        url: 'ws://127.0.0.1:$port/ws/location',
        tokenStorage: _buildTokenStorage(),
        backoffPolicy: const WsBackoffPolicy(
          initialDelay: Duration(milliseconds: 30),
          maxDelay: Duration(milliseconds: 200),
        ),
      );
      addTearDown(client.dispose);

      final states = <WsConnectionState>[];
      final sub = client.connectionState.listen(states.add);
      addTearDown(sub.cancel);

      client.connect();

      await client.connectionState
          .firstWhere((s) => s == WsConnectionState.connected)
          .timeout(const Duration(seconds: 5));

      expect(client.state, WsConnectionState.connected);
      // 최소 두 번은 재시도 경로(reconnecting)를 탔다 — 첫 시도 성공이
      // 아니라 실제로 백오프를 거쳤다는 뜻.
      expect(
        states.where((s) => s == WsConnectionState.reconnecting).length,
        greaterThanOrEqualTo(2),
      );
      expect(server.attempts, 3);
    });

    test('서버가 계속 꺼져 있으면 상한(maxAttempts)에서 포기하고, '
        '그 뒤로는 더 시도하지 않는다 — 무한 재시도 금지', () async {
      server = _FlakyStompServer(null); // 영원히 안 받아줌.
      final port = await server.start();

      final client = BaraedaWebSocketClient(
        url: 'ws://127.0.0.1:$port/ws/location',
        tokenStorage: _buildTokenStorage(),
        backoffPolicy: const WsBackoffPolicy(
          initialDelay: Duration(milliseconds: 20),
          maxDelay: Duration(milliseconds: 50),
          maxAttempts: 2,
        ),
      );
      addTearDown(client.dispose);

      client.connect();

      await client.connectionState
          .firstWhere((s) => s == WsConnectionState.gaveUp)
          .timeout(const Duration(seconds: 5));

      // maxAttempts=2 → 최초 시도 + 재시도 2회 = 총 3번 연결 시도 후 포기.
      expect(server.attempts, 3);

      // 포기한 뒤로도 시간이 더 지나면 계속 시도하는지 — 무한 재시도라면
      // 여기서 attempts 가 계속 늘어난다.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(server.attempts, 3);
    });

    // R46-FIXRT S-5 — 상한을 주지 않은 기본 정책은 서버가 오래 꺼져 있어도 포기하지 않는다. 포기하면 매니저 앱은
    // 다른 직원의 변경을 못 받고 학부모 지도는 멈춘 위치를 본 채 방치된다(터널·음영 1분 초과, 재기동 90초).
    test('상한이 없는 정책은 서버가 오래 꺼져 있어도 포기하지 않고 계속 시도한다', () async {
      server = _FlakyStompServer(null); // 영원히 안 받아줌.
      final port = await server.start();

      final client = BaraedaWebSocketClient(
        url: 'ws://127.0.0.1:$port/ws/location',
        tokenStorage: _buildTokenStorage(),
        // 상한(maxAttempts)은 일부러 주지 않는다 — 기본 정책이 곧 운영 정책이다.
        backoffPolicy: const WsBackoffPolicy(
          initialDelay: Duration(milliseconds: 10),
          maxDelay: Duration(milliseconds: 20),
        ),
      );
      addTearDown(client.dispose);
      final states = <WsConnectionState>[];
      final sub = client.connectionState.listen(states.add);
      addTearDown(sub.cancel);

      client.connect();
      await Future<void>.delayed(const Duration(milliseconds: 800));

      // 옛 기본값(6회 뒤 포기)이면 최초 1 + 재시도 6 = 7번에서 멈춘다.
      expect(server.attempts, greaterThan(10));
      expect(states, isNot(contains(WsConnectionState.gaveUp)));
      expect(client.state, isNot(WsConnectionState.gaveUp));
    });

    // 앱이 백그라운드에서 돌아왔다 — 다음 재연결 타이머(최대 30초)를 기다리지 않고 바로 붙는다.
    test('reconnectNow 는 재연결 대기 중이면 타이머를 기다리지 않고 바로 붙는다', () async {
      // 첫 시도는 거부, 둘째부터 받아 준다. 대기 간격은 일부러 길게(10초) 둔다.
      server = _FlakyStompServer(2);
      final port = await server.start();

      final client = BaraedaWebSocketClient(
        url: 'ws://127.0.0.1:$port/ws/location',
        tokenStorage: _buildTokenStorage(),
        backoffPolicy: const WsBackoffPolicy(
          initialDelay: Duration(seconds: 10),
          maxDelay: Duration(seconds: 10),
          jitterRatio: 0,
        ),
      );
      addTearDown(client.dispose);

      client.connect();
      await client.connectionState
          .firstWhere((s) => s == WsConnectionState.reconnecting)
          .timeout(const Duration(seconds: 5));
      expect(server.attempts, 1, reason: '10초 대기 중이라 아직 한 번뿐이다');

      client.reconnectNow();

      await client.connectionState
          .firstWhere((s) => s == WsConnectionState.connected)
          .timeout(const Duration(seconds: 3));
      expect(server.attempts, 2);
    });

    test('reconnectNow 는 일부러 끊은 연결·연결한 적 없는 연결·이미 연결된 연결을 건드리지 않는다', () async {
      server = _FlakyStompServer(1); // 처음부터 받아 준다.
      final port = await server.start();

      final client = BaraedaWebSocketClient(
        url: 'ws://127.0.0.1:$port/ws/location',
        tokenStorage: _buildTokenStorage(),
      );
      addTearDown(client.dispose);

      // 연결한 적 없다 — 앱 복귀만으로 소켓을 새로 열면 안 된다.
      client.reconnectNow();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(server.attempts, 0);

      // 이미 연결됐다 — 시도가 늘지 않는다.
      client.connect();
      await client.connectionState
          .firstWhere((s) => s == WsConnectionState.connected)
          .timeout(const Duration(seconds: 3));
      client.reconnectNow();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(server.attempts, 1);

      // 일부러 끊었다(거부·로그아웃) — 되살리지 않는다.
      client
        ..disconnect()
        ..reconnectNow();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(server.attempts, 1);
      expect(client.state, WsConnectionState.disconnected);
    });
  });
}
