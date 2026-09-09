import 'package:baraeda_core/storage/token_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// 실제 플랫폼 채널 없이 값만 메모리에 담아 두는 가짜 구현.
// `extends` 대신 `with MockPlatformInterfaceMixin` 을 써서 PlatformInterface
// 의 토큰 검증(verifyToken)을 우회한다 — 이 패키지 밖에서는 그 토큰을 만들 수 없다.
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

void main() {
  late _FakeSecureStoragePlatform platform;

  setUp(() {
    platform = _FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = platform;
  });

  test('주입한 키로 저장하고 그 키로만 읽는다', () async {
    final storage = TokenStorage(
      accessTokenKey: 'parent_app.access_token',
      refreshTokenKey: 'parent_app.refresh_token',
    );

    await storage.saveTokens(accessToken: 'a1', refreshToken: 'r1');

    expect(await storage.readAccessToken(), 'a1');
    expect(await storage.readRefreshToken(), 'r1');
    expect(platform.data['parent_app.access_token'], 'a1');
    expect(platform.data['parent_app.refresh_token'], 'r1');
  });

  test('두 앱이 서로 다른 키를 쓰면 서로의 토큰을 읽지 않는다', () async {
    final parentStorage = TokenStorage(
      accessTokenKey: 'parent_app.access_token',
      refreshTokenKey: 'parent_app.refresh_token',
    );
    final managerStorage = TokenStorage(
      accessTokenKey: 'manager_app.access_token',
      refreshTokenKey: 'manager_app.refresh_token',
    );

    await parentStorage.saveTokens(
      accessToken: 'parent-a',
      refreshToken: 'parent-r',
    );
    await managerStorage.saveTokens(
      accessToken: 'manager-a',
      refreshToken: 'manager-r',
    );

    expect(await parentStorage.readAccessToken(), 'parent-a');
    expect(await managerStorage.readAccessToken(), 'manager-a');
    expect(await parentStorage.readAccessToken(), isNot('manager-a'));
  });

  test('clear 는 그 인스턴스의 키만 지운다', () async {
    final storage = TokenStorage(
      accessTokenKey: 'access',
      refreshTokenKey: 'refresh',
    );
    await storage.saveTokens(accessToken: 'a1', refreshToken: 'r1');

    await storage.clear();

    expect(await storage.readAccessToken(), isNull);
    expect(await storage.readRefreshToken(), isNull);
  });
}
