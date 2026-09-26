import 'dart:convert';
import 'dart:typed_data';

import 'package:baraeda_core/network/token_refresher.dart';
import 'package:baraeda_core/storage/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// api_client_auth_test.dart 와 같은 구조의 가짜 — 이 파일만 단독으로 돌 수
// 있어야 하므로 복사해 둔다(그 파일의 관례를 그대로 따른다).
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

/// `/auth/refresh` 호출마다 순서대로 응답하는 가짜 어댑터 — 호출 수를 세어
/// "동시 재발급은 1회만 나간다"(완료 조건 9)를 검증하는 데 쓴다.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.responses);

  final List<ResponseBody Function()> responses;
  int callCount = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    callCount += 1;
    return responses.removeAt(0)();
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

TokenStorage _buildTokenStorage() {
  FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
  return TokenStorage(accessTokenKey: 'access', refreshTokenKey: 'refresh');
}

/// 실제 배선(`ApiClient` 생성자)은 `refreshDio` 에 봉투 해제 인터셉터를
/// 미리 붙여 준다(API_SPEC §1.1 — 2xx 응답은 `{success, data, message}` 로
/// 감싸져 온다) — `TokenRefresher` 는 그 결과가 이미 풀린 `data` 인 것을
/// 전제한다. 이 시험은 `ApiClient` 없이 단독으로 돌아 같은 전제를 직접
/// 갖춰 준다.
Dio _dioWithAdapter(HttpClientAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(
        InterceptorsWrapper(
          onResponse: (response, handler) {
            final body = response.data;
            if (body is Map<String, dynamic> && body.containsKey('data')) {
              response.data = body['data'];
            }
            handler.next(response);
          },
        ),
      );

void main() {
  group('TokenRefresher — REST(ApiClient)·WS 가 공유하는 재발급 창구', () {
    test('성공하면 새 토큰 쌍을 저장하고 access 토큰을 돌려준다', () async {
      final storage = _buildTokenStorage();
      await storage.saveTokens(accessToken: 'old-access', refreshToken: 'r1');

      final adapter = _ScriptedAdapter([
        () => _json(200, {
          'success': true,
          'data': {'access_token': 'new-access', 'refresh_token': 'new-r'},
          'message': null,
        }),
      ]);
      final refresher = TokenRefresher(
        refreshDio: _dioWithAdapter(adapter),
        tokenStorage: storage,
        clientType: 'app',
      );

      final token = await refresher.refresh();

      expect(token, 'new-access');
      expect(await storage.readAccessToken(), 'new-access');
      expect(await storage.readRefreshToken(), 'new-r');
      expect(adapter.callCount, 1);
    });

    test('저장된 refresh 토큰이 없으면 HTTP 호출 없이 null 을 돌려준다', () async {
      final storage = _buildTokenStorage();
      final adapter = _ScriptedAdapter([() => _json(200, {})]);
      final refresher = TokenRefresher(
        refreshDio: _dioWithAdapter(adapter),
        tokenStorage: storage,
        clientType: 'app',
      );

      final token = await refresher.refresh();

      expect(token, isNull);
      expect(adapter.callCount, 0);
    });

    test('서버가 401 로 거절하면 저장된 토큰을 지우고 null 을 돌려준다', () async {
      final storage = _buildTokenStorage();
      await storage.saveTokens(
        accessToken: 'old-access',
        refreshToken: 'invalid',
      );

      final adapter = _ScriptedAdapter([
        () => _json(401, {
          'error': {'code': 'TOKEN_EXPIRED', 'message': '만료'},
        }),
      ]);
      final refresher = TokenRefresher(
        refreshDio: _dioWithAdapter(adapter),
        tokenStorage: storage,
        clientType: 'app',
      );

      final token = await refresher.refresh();

      expect(token, isNull);
      expect(await storage.readAccessToken(), isNull);
      expect(await storage.readRefreshToken(), isNull);
    });

    test(
      '동시에 여러 번 부르면 HTTP 호출은 1회만 나가고 전부 같은 결과를 받는다 — '
      'REST·WS 가 같은 refresh 토큰으로 경합해도 회전이 두 번 일어나지 않는다 '
      '(백엔드 RefreshCommandService 의 1회용 회전, 보고서 §1)',
      () async {
        final storage = _buildTokenStorage();
        await storage.saveTokens(
          accessToken: 'old-access',
          refreshToken: 'r1',
        );

        final adapter = _ScriptedAdapter([
          () => _json(200, {
            'success': true,
            'data': {'access_token': 'new-access', 'refresh_token': 'new-r'},
            'message': null,
          }),
        ]);
        final refresher = TokenRefresher(
          refreshDio: _dioWithAdapter(adapter),
          tokenStorage: storage,
          clientType: 'app',
        );

        final results = await Future.wait<String?>([
          refresher.refresh(),
          refresher.refresh(),
          refresher.refresh(),
        ]);

        expect(adapter.callCount, 1);
        expect(results, ['new-access', 'new-access', 'new-access']);
      },
    );

    test('재발급이 끝난 뒤 다시 부르면 새 HTTP 호출이 나간다(단일 실행 결과를 계속 재사용하지 않는다)', () async {
      final storage = _buildTokenStorage();
      await storage.saveTokens(accessToken: 'a1', refreshToken: 'r1');

      final adapter = _ScriptedAdapter([
        () => _json(200, {
          'success': true,
          'data': {'access_token': 'a2', 'refresh_token': 'r2'},
          'message': null,
        }),
        () => _json(200, {
          'success': true,
          'data': {'access_token': 'a3', 'refresh_token': 'r3'},
          'message': null,
        }),
      ]);
      final refresher = TokenRefresher(
        refreshDio: _dioWithAdapter(adapter),
        tokenStorage: storage,
        clientType: 'app',
      );

      final first = await refresher.refresh();
      final second = await refresher.refresh();

      expect(first, 'a2');
      expect(second, 'a3');
      expect(adapter.callCount, 2);
    });
  });
}
