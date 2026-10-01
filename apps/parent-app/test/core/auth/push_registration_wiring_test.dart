import 'dart:convert';
import 'dart:typed_data';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';

/// NTF-12 · Ruling 510 — 학부모 앱의 `di.dart` 가 단말 등록기를 `AuthApi` 에
/// 실제로 물렸는지 본다(공유 패키지 시험은 `AuthApi` 단독이라 이 배선은 못 잡는다).
/// 로그인 뒤 가짜 공급자의 토큰이 `POST /me/devices` 로 나가고, 로그아웃은
/// 그 기기의 `device_id` 를 싣는다.

/// 시크릿 스토리지 플랫폼 채널을 타지 않는 메모리 토큰 저장소.
class _MemoryTokenStorage extends TokenStorage {
  _MemoryTokenStorage()
    : super(accessTokenKey: 'access', refreshTokenKey: 'refresh');

  String? _access;
  String? _refresh;

  @override
  Future<String?> readAccessToken() async => _access;

  @override
  Future<String?> readRefreshToken() async => _refresh;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _access = accessToken;
    _refresh = refreshToken;
  }

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
  }
}

class _MemoryStorage extends DeviceRegistrationStorage {
  String? token;

  @override
  Future<String> readOrCreateDeviceId() async => 'device-1';

  @override
  Future<String?> readDeviceId() async => 'device-1';

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String token) async => this.token = token;

  @override
  Future<void> clearToken() async => token = null;

  @override
  Future<bool> readOptedOut() async => false;
}

class _FixedTokenSource implements PushTokenSource {
  @override
  Future<String?> currentToken() async => 'fcm-1';

  @override
  Stream<void> get onMessage => const Stream.empty();
}

class _RecordingAdapter implements HttpClientAdapter {
  final List<(String, Object?)> calls = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add((options.path, options.data));
    final data = switch (options.path) {
      '/auth/login' => {
        'access_token': 'a1',
        'refresh_token': 'r1',
        'account_id': '1',
        'role': 'parent',
        'status': 'active',
      },
      '/me/devices' => {
        'device_id': 'device-1',
        'registered_at': '2026-10-01T00:00:00Z',
      },
      _ => null,
    };
    return ResponseBody.fromString(
      jsonEncode({'success': true, 'data': data}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  test('로그인하면 공급자 토큰을 등록하고 로그아웃은 device_id 를 싣는다', () async {
    final adapter = _RecordingAdapter();
    final tokenStorage = _MemoryTokenStorage();
    final apiClient = ApiClient(
      tokenStorage: tokenStorage,
      baseUrl: 'https://api.test',
    );
    apiClient.dio.httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [
        tokenStorageProvider.overrideWithValue(tokenStorage),
        apiClientProvider.overrideWithValue(apiClient),
        deviceRegistrationStorageProvider.overrideWithValue(_MemoryStorage()),
        pushTokenSourceProvider.overrideWithValue(_FixedTokenSource()),
      ],
    );
    addTearDown(container.dispose);
    final repository = container.read(authRepositoryProvider);

    await repository.login(loginId: 'parent1', password: 'pw');
    await repository.logout();

    final register = adapter.calls.singleWhere((c) => c.$1 == '/me/devices');
    expect((register.$2! as Map<String, dynamic>)['token'], 'fcm-1');
    final logout = adapter.calls.singleWhere((c) => c.$1 == '/auth/logout');
    expect((logout.$2! as Map<String, dynamic>)['device_id'], 'device-1');
  });
}
