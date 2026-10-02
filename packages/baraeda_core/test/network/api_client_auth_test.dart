import 'dart:convert';
import 'dart:typed_data';

import 'package:baraeda_core/network/api_client.dart';
import 'package:baraeda_core/storage/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// 실제 시크릿 스토리지 없이 값만 메모리에 담아 두는 가짜 구현. token_storage_test.dart 와 같은 구조.
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

  // flutter_secure_storage_platform_interface 2.1.0 이 더한 추상 메서드. 이 가짜는 저장소
  // 동작만 흉내 내므로 이관이 필요 없다는 뜻의 ok 를 돌려준다.
  @override
  Future<SecureStorageUpgradeStatus> checkUpgradeStatus({
    required Map<String, String> options,
  }) async => const SecureStorageUpgradeStatus(
    state: SecureStorageUpgradeState.ok,
  );
}

/// 응답을 경로별로 미리 정해 둔 순서대로 돌려주는 가짜 dio 어댑터.
/// 진짜 네트워크 없이 `ApiClient` 의 인터셉터 동작만 검증한다.
class _ScriptedAdapter implements HttpClientAdapter {
  new(this.responsesByPath);

  final Map<String, List<ResponseBody Function()>> responsesByPath;
  final List<String> calledPaths = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calledPaths.add(options.path);
    final queue = responsesByPath[options.path];
    if (queue == null || queue.isEmpty) {
      throw StateError('예정에 없는 요청: ${options.path}');
    }
    return queue.removeAt(0)();
  }
}

ResponseBody _json(int statusCode, Map<String, dynamic> body) =>
    ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// 본 요청용 dio 와 refresh 전용 dio **둘 다** 같은 가짜 어댑터를 쓰게 조립한다.
/// refresh 는 인터셉터가 붙지 않은 별도 인스턴스로 나가므로(재귀 방지),
/// 어댑터를 한쪽에만 물리면 실제 네트워크로 새어 시험이 무의미해진다.
ApiClient _clientWith(TokenStorage storage, _ScriptedAdapter adapter) {
  final refreshDio = Dio(BaseOptions(baseUrl: 'https://api.test'))
    ..httpClientAdapter = adapter;
  final client = ApiClient(
    tokenStorage: storage,
    baseUrl: 'https://api.test',
    refreshDio: refreshDio,
  );
  client.dio.httpClientAdapter = adapter;
  return client;
}

void main() {
  late _FakeSecureStoragePlatform platform;

  setUp(() {
    platform = _FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = platform;
  });

  TokenStorage tokenStorage() =>
      TokenStorage(accessTokenKey: 'access', refreshTokenKey: 'refresh');

  test('401 을 받으면 refresh 후 원 요청을 1회 재시도해 성공한다', () async {
    final storage = tokenStorage();
    await storage.saveTokens(accessToken: 'expired', refreshToken: 'r1');

    final adapter = _ScriptedAdapter({
      '/students/1': [
        () => _json(401, {
          'error': {'code': 'TOKEN_EXPIRED', 'message': '만료'},
        }),
        // 성공 응답은 API_SPEC §1.1 봉투로 감싸져 온다 — 클라이언트는
        // `data` 안쪽만 보게 된다(아래 `expect(response.data, ...)` 참고).
        () => _json(200, {
          'success': true,
          'data': {'id': 1, 'name': '학생'},
          'message': null,
        }),
      ],
      '/auth/refresh': [
        () => _json(200, {
          'success': true,
          'data': {
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
          },
          'message': null,
        }),
      ],
    });

    final client = _clientWith(storage, adapter);

    final response = await client.dio.get<Map<String, dynamic>>('/students/1');

    expect(response.statusCode, 200);
    expect(response.data, {'id': 1, 'name': '학생'});
    // 원 요청 2회(최초 401 + 재시도 성공) + refresh 1회 = 3콜, /students/1 로 두 번만 나가고
    // 무한 재시도로 새지 않는다.
    expect(adapter.calledPaths, [
      '/students/1',
      '/auth/refresh',
      '/students/1',
    ]);
    expect(await storage.readAccessToken(), 'new-access');
    expect(await storage.readRefreshToken(), 'new-refresh');
  });

  test('refresh 자체가 401 이면 refresh 를 한 번만 부르고 토큰을 지운다', () async {
    // 재귀 방지 회귀 시험. refresh 를 인터셉터가 붙은 같은 dio 로 보내면
    // 그 401 응답이 같은 onError 를 다시 거쳐 refresh 를 계속 재시도한다
    // — `_retriedKey` 는 "원 요청" 에만 찍히고 refresh 요청에는 안 찍히기
    // 때문이다. access·refresh 가 둘 다 만료된 실제 상황이 정확히 그 경우라
    // 무한 재귀가 된다(고치기 전 51회까지 관측). refresh 전용 dio 를 따로
    // 두는 것이 그 재귀를 구조적으로 막는다.
    final storage = tokenStorage();
    await storage.saveTokens(accessToken: 'expired', refreshToken: 'invalid');

    final adapter = _ScriptedAdapter({
      '/students/1': [
        () => _json(401, {
          'error': {'code': 'TOKEN_EXPIRED', 'message': '만료'},
        }),
      ],
      // 응답을 넉넉히 넣어 둔다 — 재귀가 살아 있으면 큐가 바닥나서가 아니라
      // 호출 횟수로 드러나야 한다.
      '/auth/refresh': List.generate(
        5,
        (_) =>
            () => _json(401, {
              'error': {'code': 'TOKEN_EXPIRED', 'message': 'refresh 도 만료'},
            }),
      ),
    });

    final client = _clientWith(storage, adapter);

    await expectLater(
      client.dio.get<dynamic>('/students/1'),
      throwsA(isA<DioException>()),
    );

    // 재발급이 실패했으니 저장된 토큰은 지워지고 로그인 화면으로 가야 한다.
    expect(await storage.readAccessToken(), isNull);
    expect(await storage.readRefreshToken(), isNull);
    // 핵심 단언 — refresh 는 정확히 1회.
    expect(
      adapter.calledPaths.where((p) => p == '/auth/refresh').length,
      1,
    );
    expect(adapter.calledPaths, ['/students/1', '/auth/refresh']);
  });

  test('access 토큰이 있으면 Authorization 헤더를 붙여 보낸다', () async {
    final storage = tokenStorage();
    await storage.saveTokens(accessToken: 'valid-token', refreshToken: 'r1');

    RequestOptions? captured;
    final adapter = _ScriptedAdapter({
      '/students/1': [
        () => _json(200, {'ok': true}),
      ],
    });

    final client = ApiClient(
      tokenStorage: storage,
      baseUrl: 'https://api.test',
    );
    client.dio.httpClientAdapter = adapter;
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.next(options);
        },
      ),
    );

    await client.dio.get<dynamic>('/students/1');

    expect(captured?.headers['Authorization'], 'Bearer valid-token');
    expect(captured?.headers['X-Client-Type'], 'app');
  });

  test('성공 응답의 data 봉투를 벗겨 돌려준다', () async {
    // api_client.dart 의 실제 진단된 결함 — 서버는 2xx 를
    // `{success, data, message}` 로 감싸는데 예전 코드는 이 봉투를 벗기지
    // 않고 루트에서 필드를 읽었다. 이 시험은 그 결함을 refresh 흐름과
    // 무관하게 일반 GET 응답 하나로 독립 검증한다.
    final storage = tokenStorage();
    await storage.saveTokens(accessToken: 'valid', refreshToken: 'r1');

    final adapter = _ScriptedAdapter({
      '/academies': [
        () => _json(200, {
          'success': true,
          'data': {
            'items': [
              {'id': 'a1', 'name': '바래다학원'},
            ],
          },
          'message': null,
        }),
      ],
    });

    final client = _clientWith(storage, adapter);
    final response = await client.dio.get<Map<String, dynamic>>('/academies');

    expect(response.data, {
      'items': [
        {'id': 'a1', 'name': '바래다학원'},
      ],
    });
  });

  test(
    '403 AUTH_PENDING 을 받으면 어느 화면의 호출이든 gateEvents 로 신호를 보낸다',
    () async {
      final storage = tokenStorage();
      await storage.saveTokens(accessToken: 'valid', refreshToken: 'r1');

      final adapter = _ScriptedAdapter({
        '/schedule': [
          () => _json(403, {
            'error': {'code': 'AUTH_PENDING', 'message': '승인 대기 중'},
          }),
        ],
      });

      final client = _clientWith(storage, adapter);
      final events = <AccountGateReason>[];
      final sub = client.gateEvents.listen(events.add);

      await expectLater(
        client.dio.get<dynamic>('/schedule'),
        throwsA(isA<DioException>()),
      );
      // 스트림은 비동기 브로드캐스트라 리스너에 닿을 때까지 한 틱 필요.
      await Future<void>.delayed(Duration.zero);

      expect(events, [AccountGateReason.pending]);
      await sub.cancel();
      client.dispose();
    },
  );

  test(
    '403 AUTH_REJECTED 를 받으면 rejected 신호를 보낸다',
    () async {
      final storage = tokenStorage();
      await storage.saveTokens(accessToken: 'valid', refreshToken: 'r1');

      final adapter = _ScriptedAdapter({
        '/schedule': [
          () => _json(403, {
            'error': {'code': 'AUTH_REJECTED', 'message': '가입이 거절됨'},
          }),
        ],
      });

      final client = _clientWith(storage, adapter);
      final events = <AccountGateReason>[];
      final sub = client.gateEvents.listen(events.add);

      await expectLater(
        client.dio.get<dynamic>('/schedule'),
        throwsA(isA<DioException>()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, [AccountGateReason.rejected]);
      await sub.cancel();
      client.dispose();
    },
  );
  // --- F07-01 · F07-02 · F07-05 · F07-07 (2026-09-30 전체 검사) ---

  Map<String, dynamic> refreshOk() => {
    'success': true,
    'data': {'access_token': 'new-access', 'refresh_token': 'new-refresh'},
    'message': null,
  };

  test(
    '재발급에 성공한 뒤 재시도가 업무 오류(409)로 끝나면 새 토큰을 지키고 그 409 를 그대로 던진다',
    () async {
      // F07-01 — 예전 코드는 재시도가 어떤 DioException 으로 끝나도 저장소를 통째로
      // 비우고 재시도의 진짜 오류 대신 옛 401 을 돌려줬다.
      final storage = tokenStorage();
      await storage.saveTokens(accessToken: 'expired', refreshToken: 'r1');
      final adapter = _ScriptedAdapter({
        '/runs/1/arrive': [
          () => _json(401, {
            'error': {'code': 'TOKEN_EXPIRED', 'message': '만료'},
          }),
          () => _json(409, {
            'error': {'code': 'DUPLICATE_ARRIVE', 'message': '이미 도착 처리'},
          }),
        ],
        '/auth/refresh': [() => _json(200, refreshOk())],
      });
      final client = _clientWith(storage, adapter);
      var sessionExpiredCount = 0;
      final sub = client.sessionExpired.listen((_) => sessionExpiredCount += 1);

      final error = await client.dio
          .post<dynamic>('/runs/1/arrive')
          .then<DioException?>((_) => null)
          .catchError((Object e) => e as DioException);

      expect(error?.response?.statusCode, 409);
      expect(await storage.readAccessToken(), 'new-access');
      expect(await storage.readRefreshToken(), 'new-refresh');
      await Future<void>.delayed(Duration.zero);
      expect(sessionExpiredCount, 0);
      await sub.cancel();
      client.dispose();
    },
  );

  test(
    '재발급 요청이 네트워크 오류로 실패하면 토큰을 지우지 않고 그 네트워크 오류를 던진다',
    () async {
      // F07-02 — 일시 장애를 로그아웃으로 옮기지 않는다.
      final storage = tokenStorage();
      await storage.saveTokens(accessToken: 'expired', refreshToken: 'r1');
      final adapter = _ScriptedAdapter({
        '/students/1': [
          () => _json(401, {
            'error': {'code': 'TOKEN_EXPIRED', 'message': '만료'},
          }),
        ],
        '/auth/refresh': [
          () => throw DioException.connectionError(
            requestOptions: RequestOptions(path: '/auth/refresh'),
            reason: '연결 끊김',
          ),
        ],
      });
      final client = _clientWith(storage, adapter);
      var sessionExpiredCount = 0;
      final sub = client.sessionExpired.listen((_) => sessionExpiredCount += 1);

      final error = await client.dio
          .get<dynamic>('/students/1')
          .then<DioException?>((_) => null)
          .catchError((Object e) => e as DioException);

      expect(error?.type, DioExceptionType.connectionError);
      expect(await storage.readAccessToken(), 'expired');
      expect(await storage.readRefreshToken(), 'r1');
      await Future<void>.delayed(Duration.zero);
      expect(sessionExpiredCount, 0);
      await sub.cancel();
      client.dispose();
    },
  );

  test(
    '재발급을 서버가 401 로 거절하면 sessionExpired 로 한 번 알린다 — REST 에도 재로그인 신호가 있다',
    () async {
      // F07-07 — 예전엔 WS 쪽에만 만료 신호가 있어 REST 만 쓰는 화면은 토큰이 지워져도
      // 요청마다 401 띠만 반복했다.
      final storage = tokenStorage();
      await storage.saveTokens(accessToken: 'expired', refreshToken: 'dead');
      final adapter = _ScriptedAdapter({
        '/students/1': [
          () => _json(401, {
            'error': {'code': 'TOKEN_EXPIRED', 'message': '만료'},
          }),
        ],
        '/auth/refresh': [
          () => _json(401, {
            'error': {'code': 'TOKEN_EXPIRED', 'message': 'refresh 무효'},
          }),
        ],
      });
      final client = _clientWith(storage, adapter);
      var sessionExpiredCount = 0;
      final sub = client.sessionExpired.listen((_) => sessionExpiredCount += 1);

      await expectLater(
        client.dio.get<dynamic>('/students/1'),
        throwsA(isA<DioException>()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(sessionExpiredCount, 1);
      await sub.cancel();
      client.dispose();
    },
  );

  test('저장된 토큰이 없는 로그인 실패(401)는 sessionExpired 를 울리지 않는다', () async {
    final storage = tokenStorage();
    final adapter = _ScriptedAdapter({
      '/auth/login': [
        () => _json(401, {
          'error': {'code': 'INVALID_CREDENTIALS', 'message': '불일치'},
        }),
      ],
    });
    final client = _clientWith(storage, adapter);
    var sessionExpiredCount = 0;
    final sub = client.sessionExpired.listen((_) => sessionExpiredCount += 1);

    await expectLater(
      client.dio.post<dynamic>('/auth/login'),
      throwsA(isA<DioException>()),
    );
    await Future<void>.delayed(Duration.zero);

    expect(sessionExpiredCount, 0);
    await sub.cancel();
    client.dispose();
  });

  test('기본 dio 와 재발급 dio 는 연결·송신·수신 제한 시간을 갖는다', () {
    // F07-05 — dio 5 의 기본은 제한 없음이다. 재발급 하나가 멈추면 합류한 모든 요청이
    // 같이 멈춘다.
    final client = ApiClient(
      tokenStorage: tokenStorage(),
      baseUrl: 'https://api.test',
    );
    for (final dio in [client.dio, client.refreshDio]) {
      expect(dio.options.connectTimeout, isNotNull);
      expect(dio.options.sendTimeout, isNotNull);
      expect(dio.options.receiveTimeout, isNotNull);
    }
    client.dispose();
  });
}
