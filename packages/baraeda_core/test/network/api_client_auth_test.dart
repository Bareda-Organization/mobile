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
}

/// 응답을 경로별로 미리 정해 둔 순서대로 돌려주는 가짜 dio 어댑터.
/// 진짜 네트워크 없이 `ApiClient` 의 인터셉터 동작만 검증한다.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.responsesByPath);

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
        () => _json(200, {'id': 1, 'name': '학생'}),
      ],
      '/auth/refresh': [
        () => _json(200, {
          'access_token': 'new-access',
          'refresh_token': 'new-refresh',
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
}
