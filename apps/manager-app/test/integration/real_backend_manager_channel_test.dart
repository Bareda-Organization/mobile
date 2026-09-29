@Tags(['real_backend'])
library;

import 'dart:io';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import '../support/real_backend_target.dart';

// `real_backend_run_flow_test.dart`(F4-A, manager-app) 와 같은 구조 — 진짜
// 소켓 스토리지 대신 메모리에만 담는다.
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

/// `/topic/manager/runs/{runId}`(§5.4.1 목표 6) 구독 인가를 실제 서버로
/// 확인하는 계약 시험 — `real_backend_p3_test.dart`(parent-app, 학생 채널)
/// 와 같은 구조를 이 앱이 실제로 구독하는 채널 하나에 맞춰 좁힌 것.
/// `manager_run_channel_test.dart`(단위 시험, 있다면)는 가짜 클라이언트로
/// 화면 로직만 보므로, 서버가 이 채널을 **실제로 허용·거부하는지**는 이
/// 파일이 담당한다.
///
/// 시드(`V2__seed_data.sql`) 기준 — `driverA1`(manager_id=1)·`escortA1`
/// (manager_id=3)은 회차 1·2·7에 배치돼 있고 회차 3(다른 기사·동승자 배치)
/// 에는 배치돼 있지 않다. "구독이 붙는다"만 보면 아무 회차나 다 통과하는
/// 것과 구별되지 않으므로, 배치되지 않은 회차로 거부되는 부정 확인을
/// 각 역할마다 반드시 짝지어 둔다.
void main() {
  final baseUrl = requireRealBackendBaseUrl();
  final wsUrl = wsUrlFromApiBaseUrl(baseUrl);

  late bool backendReachable;

  setUpAll(() async {
    // widget test 바인딩이 HttpOverrides.global 을 항상 400 을 주는 대역으로
    // 바꿔 두므로(형제 파일들과 같은 함정), 이 파일이 도는 동안만 끈다.
    HttpOverrides.global = null;
    final probe = Dio(BaseOptions(baseUrl: baseUrl));
    try {
      await probe.get<dynamic>('/manager/runs');
      backendReachable = true;
    } on DioException catch (e) {
      backendReachable = e.response != null;
    } finally {
      probe.close();
    }
  });

  Future<TokenStorage> login(String loginId, String storagePrefix) async {
    FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
    final storage = TokenStorage(
      accessTokenKey: '$storagePrefix-access',
      refreshTokenKey: '$storagePrefix-refresh',
    );
    final client = ApiClient(tokenStorage: storage, baseUrl: baseUrl);
    final auth = AuthApi(dio: client.dio, tokenStorage: storage);
    await auth.login(loginId: loginId, password: 'password');
    return storage;
  }

  test(
    '목표 6 — 기사(driverA1)가 배치된 회차(1)의 매니저 채널을 구독하면 '
    '거부되지 않는다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final storage = await login('driverA1', 'mgr-driver-assigned');
      final client = BaraedaWebSocketClient(url: wsUrl, tokenStorage: storage);
      addTearDown(client.dispose);

      client.connect();
      await client.connectionState
          .firstWhere((s) => s == WsConnectionState.connected)
          .timeout(const Duration(seconds: 10));

      final forbidden = client.forbiddenSubscriptions
          .firstWhere((d) => d == WsChannel.managerRun('1'))
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () => '__no-forbidden__',
          );

      client.subscribe(WsChannel.managerRun('1'), (_) {});

      expect(await forbidden, '__no-forbidden__');
    },
  );

  test(
    '목표 6 — 기사(driverA1)가 배치되지 않은 회차(3)의 매니저 채널을 '
    '구독하면 forbiddenSubscriptions 에 그 목적지가 실린다 (위 시험과 짝을 '
    '이루는 부정 확인 — "붙는다"만 보여서는 아무 회차나 보이는 것과 '
    '구별되지 않는다)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final storage = await login('driverA1', 'mgr-driver-unassigned');
      final client = BaraedaWebSocketClient(url: wsUrl, tokenStorage: storage);
      addTearDown(client.dispose);

      client.connect();
      await client.connectionState
          .firstWhere((s) => s == WsConnectionState.connected)
          .timeout(const Duration(seconds: 10));

      final forbidden = client.forbiddenSubscriptions
          .firstWhere((d) => d == WsChannel.managerRun('3'))
          .timeout(const Duration(seconds: 10));

      client.subscribe(WsChannel.managerRun('3'), (_) {});

      expect(await forbidden, WsChannel.managerRun('3'));
    },
  );

  test(
    '목표 6 — 동승자(escortA1)가 배치된 회차(1)의 매니저 채널을 구독하면 '
    '거부되지 않는다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final storage = await login('escortA1', 'mgr-escort-assigned');
      final client = BaraedaWebSocketClient(url: wsUrl, tokenStorage: storage);
      addTearDown(client.dispose);

      client.connect();
      await client.connectionState
          .firstWhere((s) => s == WsConnectionState.connected)
          .timeout(const Duration(seconds: 10));

      final forbidden = client.forbiddenSubscriptions
          .firstWhere((d) => d == WsChannel.managerRun('1'))
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () => '__no-forbidden__',
          );

      client.subscribe(WsChannel.managerRun('1'), (_) {});

      expect(await forbidden, '__no-forbidden__');
    },
  );

  test(
    '목표 6 — 동승자(escortA1)가 배치되지 않은 회차(3)의 매니저 채널을 '
    '구독하면 거부된다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final storage = await login('escortA1', 'mgr-escort-unassigned');
      final client = BaraedaWebSocketClient(url: wsUrl, tokenStorage: storage);
      addTearDown(client.dispose);

      client.connect();
      await client.connectionState
          .firstWhere((s) => s == WsConnectionState.connected)
          .timeout(const Duration(seconds: 10));

      final forbidden = client.forbiddenSubscriptions
          .firstWhere((d) => d == WsChannel.managerRun('3'))
          .timeout(const Duration(seconds: 10));

      client.subscribe(WsChannel.managerRun('3'), (_) {});

      expect(await forbidden, WsChannel.managerRun('3'));
    },
  );
}
