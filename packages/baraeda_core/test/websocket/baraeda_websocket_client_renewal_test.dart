import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// 접근 토큰 만료 전 갱신(Ruling 901) — 실제 소켓을 받는 가짜 STOMP 서버로 순서를 잰다.
// 판정 대상은 "만료 lead 전 재발급 → 지금 연결을 닫음 → 새 토큰으로 다시 접속(연결은 언제나 1개) →
// 화면이 `connected` 를 받아 재구독 · REST 재조회 한 번" 한 줄기다.

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
  }) async =>
      const SecureStorageUpgradeStatus(state: SecureStorageUpgradeState.ok);
}

Future<TokenStorage> _storageWith(String accessToken) async {
  FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
  final storage = TokenStorage(
    accessTokenKey: 'access',
    refreshTokenKey: 'refresh',
  );
  await storage.saveTokens(accessToken: accessToken, refreshToken: 'r1');
  return storage;
}

/// `exp`(초)만 든 서명 없는 JWT — 클라이언트는 만료 시각만 읽는다.
String _jwtExpiringIn(Duration remaining) {
  String encode(Map<String, Object?> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final exp = DateTime.now().add(remaining).millisecondsSinceEpoch ~/ 1000;
  return '${encode({'alg': 'HS256'})}.${encode({'exp': exp})}.sig';
}

const _destination = '/topic/a';

// 시험이 시간을 줄여 쓴다 — 운영 값(60초 전)은 `TokenRenewalTiming` 기본값.
const _fastTiming = TokenRenewalTiming(
  lead: Duration(seconds: 3),
  minDelay: Duration.zero,
);

String _envelope(int n) =>
    '{"event":"position","run_id":"$n",'
    '"occurred_at":"2026-10-01T00:00:00Z","payload":{}}';

class _Conn {
  new(this.index, this.socket);
  final int index;
  final WebSocket socket;
  String? auth;
  final List<String> subscriptionIds = [];
  bool closed = false;
}

/// 연결을 여러 개 받는 가짜 서버 — 연결별 CONNECT · DISCONNECT · 구독 · 닫힘을 순서대로 [events] 에 남긴다.
class _RenewalServer {
  final List<_Conn> conns = [];
  final List<String> events = [];
  HttpServer? _server;

  Future<int> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      final conn = _Conn(conns.length, socket);
      conns.add(conn);
      unawaited(
        socket.done.then((_) {
          conn.closed = true;
          events.add('closed:${conn.index}');
        }),
      );
      socket.listen((dynamic data) {
        final text = data is String ? data : '';
        if (text.startsWith('CONNECT')) {
          for (final line in text.split('\n')) {
            if (line.startsWith('Authorization:')) {
              conn.auth = line.substring('Authorization:'.length);
            }
          }
          events.add('connect:${conn.index}');
          _send(conn, 'CONNECTED\nversion:1.2\n\n\x00');
        } else if (text.startsWith('SUBSCRIBE')) {
          final id = RegExp(r'id:(\S+)').firstMatch(text)?.group(1);
          final destination = RegExp(r'destination:(\S+)')
              .firstMatch(text)
              ?.group(1);
          events.add('subscribe:${conn.index}:$destination');
          if (id != null) conn.subscriptionIds.add(id);
        } else if (text.startsWith('DISCONNECT')) {
          events.add('disconnect:${conn.index}');
          // 실서버처럼 DISCONNECT 의 receipt 에 답해야 클라이언트가 소켓을 닫는다.
          final receipt = RegExp(r'receipt:(\S+)').firstMatch(text)?.group(1);
          if (receipt != null) {
            _send(conn, 'RECEIPT\nreceipt-id:$receipt\n\n\x00');
          }
        }
      });
    });
    return server.port;
  }

  /// 상대가 닫는 순간과 겹친 쓰기는 버린다 — `readyState` 가 아직 열림이어도 싱크는
  /// 이미 닫혀 있을 수 있다(실서버도 같은 경합을 겪는다).
  void _send(_Conn conn, String frame) {
    try {
      conn.socket.add(frame);
      // 시험 가짜 서버라 닫힘 경합의 StateError 만 무시한다.
      // ignore: avoid_catching_errors
    } on StateError {
      events.add('dropped:${conn.index}:${frame.split('\n').first}');
    }
  }

  /// [index] 번 연결의 구독자에게 MESSAGE 하나를 보낸다.
  void push(int index, String body) {
    final conn = conns[index];
    conn.socket.add(
      'MESSAGE\nsubscription:${conn.subscriptionIds.first}\n'
      'destination:$_destination\n'
      'message-id:${DateTime.now().microsecondsSinceEpoch}\n'
      'content-type:application/json\n\n$body\x00',
    );
  }

  Future<void> stop() async {
    for (final conn in conns) {
      await conn.socket.close();
    }
    await _server?.close(force: true);
  }
}

Future<void> _until(bool Function() condition, {String? what}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 6));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('시간 안에 안 됨: $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<void> _connected(BaraedaWebSocketClient client) => client.connectionState
    .firstWhere((s) => s == WsConnectionState.connected)
    .timeout(const Duration(seconds: 5));

void main() {
  group('BaraedaWebSocketClient — 만료 전 갱신(Ruling 901)', () {
    late _RenewalServer server;

    tearDown(() async {
      await server.stop();
    });

    Future<({BaraedaWebSocketClient client, List<String> refreshed})> start({
      required Future<String?> Function(int call) refresh,
      String? initialToken,
      TokenRenewalTiming timing = _fastTiming,
    }) async {
      server = _RenewalServer();
      final port = await server.start();
      final refreshed = <String>[];
      var calls = 0;
      final client = BaraedaWebSocketClient(
        url: 'ws://127.0.0.1:$port/ws/location',
        tokenStorage: await _storageWith(
          initialToken ?? _jwtExpiringIn(const Duration(seconds: 4)),
        ),
        renewalTiming: timing,
        refreshAccessToken: () async {
          calls += 1;
          final token = await refresh(calls);
          if (token != null) refreshed.add(token);
          return token;
        },
      );
      addTearDown(client.dispose);
      return (client: client, refreshed: refreshed);
    }

    test('만료 전에 재발급해 지금 연결을 닫은 뒤 새 토큰으로 다시 붙는다 — 연결은 언제나 하나', () async {
      final fresh = _jwtExpiringIn(const Duration(minutes: 10));
      final started = await start(refresh: (_) async => fresh);
      final client = started.client..connect();
      await _connected(client);

      await _until(
        () => server.conns.length == 2 && server.conns[1].auth != null,
        what: '새 토큰으로 다시 접속',
      );
      await _until(() => server.conns[0].closed, what: '옛 연결 종료');

      expect(server.conns[1].auth, 'Bearer $fresh');
      // 옛 연결에 DISCONNECT 를 보낸 뒤에야 새 연결의 CONNECT 가 온다.
      expect(
        server.events.indexOf('disconnect:0'),
        lessThan(server.events.indexOf('connect:1')),
        reason: '옛 연결을 닫기 전에 새 연결을 열었다 — 두 번째 연결이 생겼다',
      );
      expect(server.conns, hasLength(2));
    });

    test(
      '다시 붙을 때 connecting → connected 가 한 번씩 나가 화면이 재구독 · REST 재조회를 한 번 한다',
      () async {
        final started = await start(
          refresh: (_) async => _jwtExpiringIn(const Duration(minutes: 10)),
        );
        final client = started.client..connect();
        await _connected(client);
        final states = <WsConnectionState>[];
        final sub = client.connectionState.listen(states.add);
        addTearDown(sub.cancel);

        await _until(() => server.conns.length == 2, what: '다시 접속');
        await _until(() => states.contains(WsConnectionState.connected));
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(states, [
          WsConnectionState.connecting,
          WsConnectionState.connected,
        ]);
        expect(server.conns, hasLength(2), reason: '옛 연결의 닫힘을 끊김으로 오인해 또 붙었다');
      },
    );

    test('화면이 connected 마다 구독하면 다시 붙은 새 연결의 방송을 받는다', () async {
      final started = await start(
        refresh: (_) async => _jwtExpiringIn(const Duration(minutes: 10)),
      );
      final client = started.client;
      final received = <String>[];
      // 화면과 같은 방식 — connected 를 받을 때마다 구독한다.
      final sub = client.connectionState
          .where((s) => s == WsConnectionState.connected)
          .listen((_) {
            client.subscribe(_destination, (e) => received.add(e.runId));
          });
      addTearDown(sub.cancel);
      client.connect();

      await _until(
        () => server.events.contains('subscribe:1:$_destination'),
        what: '다시 붙은 연결의 구독',
      );
      server
        ..push(0, _envelope(1)) // 닫힌 옛 연결의 늦은 방송은 버린다
        ..push(1, _envelope(2));
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(received, ['2']);
    });

    test('만료 lead 전에 시작한다 — 일찍도 늦게도 아니다', () async {
      // 만료까지 약 5~6초, lead 3초 → 다시 붙기는 2~3초째.
      final started = await start(
        refresh: (_) async => _jwtExpiringIn(const Duration(minutes: 10)),
        initialToken: _jwtExpiringIn(const Duration(seconds: 6)),
      );
      final client = started.client..connect();
      await _connected(client);

      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(server.conns, hasLength(1), reason: '만료 lead 보다 일찍 다시 붙었다');
      await Future<void>.delayed(const Duration(milliseconds: 2300));
      expect(server.conns, hasLength(2), reason: '만료 lead 가 지났는데 다시 붙지 않았다');
    });

    test('다시 붙은 뒤에도 새 토큰의 만료 기준으로 다음 갱신이 예약된다', () async {
      final started = await start(
        refresh: (call) async => _jwtExpiringIn(
          call == 1 ? const Duration(seconds: 5) : const Duration(minutes: 10),
        ),
      );
      final client = started.client..connect();
      await _connected(client);

      await _until(() => server.conns.length == 3, what: '두 번째 갱신');
      expect(started.refreshed, hasLength(2));
    });

    test('재발급이 실패하면 연결을 그대로 두고 다시 붙지 않는다', () async {
      final started = await start(refresh: (_) async => throw Exception('net'));
      final client = started.client..connect();
      await _connected(client);
      final states = <WsConnectionState>[];
      final sub = client.connectionState.listen(states.add);
      addTearDown(sub.cancel);

      await Future<void>.delayed(const Duration(seconds: 2));

      expect(server.conns, hasLength(1));
      expect(server.conns[0].closed, isFalse);
      expect(states, isEmpty);
      expect(client.state, WsConnectionState.connected);
    });

    test('재발급이 거절돼 토큰이 없으면 연결을 그대로 둔다 — 만료 뒤 TOKEN_EXPIRED 경로가 받는다', () async {
      final started = await start(refresh: (_) async => null);
      final client = started.client..connect();
      await _connected(client);

      await Future<void>.delayed(const Duration(seconds: 2));

      expect(server.conns, hasLength(1));
      expect(server.conns[0].closed, isFalse);
      expect(client.state, WsConnectionState.connected);
    });

    test('disconnect() 하면 예약된 갱신을 취소한다', () async {
      final started = await start(
        refresh: (_) async => _jwtExpiringIn(const Duration(minutes: 10)),
      );
      final client = started.client..connect();
      await _connected(client);

      client.disconnect();
      await Future<void>.delayed(const Duration(seconds: 2));

      expect(started.refreshed, isEmpty);
      expect(server.conns, hasLength(1));
    });

    test('재발급을 기다리는 중에 disconnect() 하면 다시 붙지 않는다', () async {
      final release = Completer<String?>();
      final started = await start(refresh: (_) => release.future);
      final client = started.client..connect();
      await _connected(client);
      // 갱신 시각이 지나 재발급 호출이 걸릴 때까지 기다린다.
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      client.disconnect();
      release.complete(_jwtExpiringIn(const Duration(minutes: 10)));
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(server.conns, hasLength(1), reason: '로그아웃 뒤에 새 연결을 열었다');
      expect(client.state, WsConnectionState.disconnected);
    });

    test('만료 시각을 읽을 수 없는 토큰이면 갱신을 예약하지 않는다', () async {
      final started = await start(
        refresh: (_) async => _jwtExpiringIn(const Duration(minutes: 10)),
        initialToken: 'not-a-jwt',
      );
      final client = started.client..connect();
      await _connected(client);

      await Future<void>.delayed(const Duration(seconds: 2));

      expect(started.refreshed, isEmpty);
      expect(server.conns, hasLength(1));
    });
  });
}
