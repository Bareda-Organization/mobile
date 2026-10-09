import 'dart:convert';
import 'dart:typed_data';

import 'package:baraeda_core/auth/auth_api.dart';
import 'package:baraeda_core/push/device_registrar.dart';
import 'package:baraeda_core/push/device_registration_storage.dart';
import 'package:baraeda_core/push/placeholder_push_token_source.dart';
import 'package:baraeda_core/push/push_token_source.dart';
import 'package:baraeda_core/storage/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// NTF-12 — 로그인 뒤 단말 등록 · 로그아웃 때 해지(API_SPEC §2.7 · §2.11). 가짜 토큰 공급자와 가짜 어댑터로
// 서버에 실제로 나간 요청(경로 · 본문)을 본다.

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

/// 지정한 토큰을 돌려주는 가짜 공급자 — `null` 이면 "줄 토큰이 없는" 상태다.
class _FakeTokenSource implements PushTokenSource {
  new(this.token);

  String? token;

  @override
  Future<String?> currentToken() async => token;

  @override
  Stream<void> get onMessage => const Stream.empty();
}

class _Call {
  new(this.method, this.path, this.body);

  final String method;
  final String path;
  final Object? body;
}

/// 나간 요청을 기록하고, 경로별로 정해 둔 상태 코드로 답하는 가짜 dio 어댑터.
class _RecordingAdapter implements HttpClientAdapter {
  final List<_Call> calls = [];

  /// `/me/devices` 가 이 상태 코드로 답한다(기본 201).
  int deviceStatus = 201;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(_Call(options.method, options.path, options.data));
    // `ApiClient` 인터셉터가 벗기는 `data` 봉투는 이 시험이 순수 dio 를 쓰므로 처음부터 벗겨서 준다.
    final body = switch (options.path) {
      '/auth/login' => {
        'access_token': 'a1',
        'refresh_token': 'r1',
        'account_id': '1',
        'role': 'parent',
        'status': 'active',
      },
      '/me' => {
        'account_id': '1',
        'login_id': 'p1',
        'name': '학부모',
        'phone': '010-0000-0000',
        'role': 'parent',
        'status': 'active',
      },
      '/me/devices' => {
        'device_id': 'd',
        'registered_at': '2026-10-01T00:00:00Z',
      },
      _ => <String, dynamic>{},
    };
    final status = options.path == '/me/devices' ? deviceStatus : 200;
    return ResponseBody.fromString(
      jsonEncode(
        status >= 400
            ? {
                'error': {'code': 'X', 'message': 'x'},
              }
            : body,
      ),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  late _FakeSecureStoragePlatform platform;
  late _RecordingAdapter adapter;
  late _FakeTokenSource tokenSource;
  late DeviceRegistrationStorage deviceStorage;
  late AuthApi api;

  setUp(() {
    platform = _FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = platform;
    adapter = _RecordingAdapter();
    tokenSource = _FakeTokenSource('fcm-token-1');
    deviceStorage = DeviceRegistrationStorage();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter;
    api = AuthApi(
      dio: dio,
      tokenStorage: TokenStorage(
        accessTokenKey: 'access',
        refreshTokenKey: 'refresh',
      ),
      deviceRegistrar: DeviceRegistrar(
        tokenSource: tokenSource,
        storage: deviceStorage,
        platform: 'android',
      ),
    );
  });

  Iterable<_Call> deviceCalls() =>
      adapter.calls.where((c) => c.path == '/me/devices');

  test('로그인에 성공하면 공급자의 토큰을 단말로 등록한다', () async {
    await api.login(loginId: 'p1', password: 'pw');

    final call = deviceCalls().single;
    expect(call.method, 'POST');
    final body = call.body! as Map<String, dynamic>;
    expect(body['token'], 'fcm-token-1');
    expect(body['platform'], 'android');
    expect(body['device_id'], await deviceStorage.readOrCreateDeviceId());
    expect(await deviceStorage.readToken(), 'fcm-token-1');
  });

  test('공급자가 토큰을 못 주면(null) 등록하지 않고 로그인은 성공한다', () async {
    tokenSource.token = null;

    final response = await api.login(loginId: 'p1', password: 'pw');

    expect(response.accessToken, 'a1');
    expect(deviceCalls(), isEmpty);
  });

  test('등록이 실패해도 로그인은 성공하고, 다음 /me 가 다시 시도한다', () async {
    adapter.deviceStatus = 500;
    final response = await api.login(loginId: 'p1', password: 'pw');
    expect(response.accessToken, 'a1');
    expect(deviceCalls(), hasLength(1));

    adapter.deviceStatus = 201;
    await api.me();

    expect(deviceCalls(), hasLength(2));
  });

  test('같은 토큰은 /me 를 여러 번 불러도 한 번만 등록한다', () async {
    await api.login(loginId: 'p1', password: 'pw');
    await api.me();
    await api.me();

    expect(deviceCalls(), hasLength(1));
  });

  test('로그아웃은 등록된 기기의 device_id 를 함께 보내 서버가 그 토큰을 해지하게 한다', () async {
    await api.login(loginId: 'p1', password: 'pw');
    final deviceId = await deviceStorage.readOrCreateDeviceId();

    await api.logout();

    final logout = adapter.calls.singleWhere((c) => c.path == '/auth/logout');
    final body = logout.body! as Map<String, dynamic>;
    expect(body['device_id'], deviceId);
    expect(body['refresh_token'], 'r1');
    expect(await deviceStorage.readToken(), isNull);
  });

  test('로그아웃 뒤 다시 로그인하면 같은 토큰이라도 다시 등록한다', () async {
    await api.login(loginId: 'p1', password: 'pw');
    await api.logout();

    await api.login(loginId: 'p1', password: 'pw');

    expect(deviceCalls(), hasLength(2));
  });

  test('사용자가 기기 알림을 꺼 두었으면 로그인해도 등록하지 않는다', () async {
    await deviceStorage.saveOptedOut(optedOut: true);

    await api.login(loginId: 'p1', password: 'pw');

    expect(deviceCalls(), isEmpty);
  });

  test('기본 공급자는 기기 식별자에서 정한 같은 토큰을 매번 준다', () async {
    final source = PlaceholderPushTokenSource(deviceStorage);

    final first = await source.currentToken();
    final second = await source.currentToken();

    expect(first, 'placeholder-${await deviceStorage.readOrCreateDeviceId()}');
    expect(second, first);
  });

  // M-P3 — 화면이 "이 기기는 아직 푸시를 받을 수 없다" 를 가를 수 있어야 한다.
  test('자리표시 토큰은 자리표시로 알아보고, 진짜 토큰 · 토큰 없음은 아니라고 한다', () async {
    final source = PlaceholderPushTokenSource(deviceStorage);
    final token = await source.currentToken();

    expect(PlaceholderPushTokenSource.isPlaceholder(token), isTrue);
    expect(PlaceholderPushTokenSource.isPlaceholder('fcm-1'), isFalse);
    expect(PlaceholderPushTokenSource.isPlaceholder(null), isFalse);
  });
}
