@Tags(['real_backend'])
library;

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import '../support/real_backend_target.dart';

// 실제 시크릿 스토리지 없이 값만 메모리에 담아 두는 가짜 구현
// (`real_backend_p1_test.dart` 와 같은 구조).
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
  }) async => SecureStorageUpgradeStatus.unsupported;
}

/// `/topic/students/{studentId}/run`(§5.4.1 5번) 구독 인가를 실제 서버로
/// 확인하는 계약 시험 — `baraeda_websocket_client_connect_test.dart` 와
/// 같은 구조(완료 조건 1·2 형태)를 이 화면이 실제로 구독하는 채널 하나에
/// 맞춰 좁힌 것. `live_map_screen_test.dart` 는 가짜 클라이언트로 화면
/// 로직만 보므로, 서버가 그 채널을 **실제로 허용·거부하는지**는 이 파일이
/// 담당한다.
///
/// 시드(`V2__seed_data.sql`) 기준 — `parentA1`(guardian)은 학생 1(김철수)에
/// 연결돼 있고 학생 3(박민수)에는 연결돼 있지 않다. `studentA4`(student,
/// account 10)는 학생 4(이하늘) 본인이다.
void main() {
  // ⚠ 리터럴 포트를 박지 않는다 — `ApiConstants.baseUrl` 하나만 쓴다
  // (`real_backend_p1_test.dart` 와 같은 근거, f766c27).
  final baseUrl = requireRealBackendBaseUrl();
  final wsUrl = (() {
    final uri = Uri.parse(baseUrl);
    return uri.replace(scheme: 'ws', path: '/ws/location').toString();
  })();

  late bool backendReachable;

  setUpAll(() async {
    FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
    final probe = Dio(BaseOptions(baseUrl: baseUrl));
    try {
      await probe.get<dynamic>(
        '/academies/search',
        queryParameters: {'q': '바래다'},
      );
      backendReachable = true;
    } on DioException catch (e) {
      backendReachable = e.response != null;
    } finally {
      probe.close();
    }
  });

  Future<TokenStorage> login(String loginId, String storagePrefix) async {
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
    '목표 5 — 학부모(parentA1)가 연결된 자녀(학생 1)의 회차 채널을 구독하면 '
    '거부되지 않는다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final storage = await login('parentA1', 'p3-parent-linked');
      final client = BaraedaWebSocketClient(url: wsUrl, tokenStorage: storage);
      addTearDown(client.dispose);

      client.connect();
      await client.connectionState
          .firstWhere((s) => s == WsConnectionState.connected)
          .timeout(const Duration(seconds: 10));

      final forbidden = client.forbiddenSubscriptions
          .firstWhere((d) => d == WsChannel.studentRun('1'))
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () => '__no-forbidden__',
          );

      client.subscribe(WsChannel.studentRun('1'), (_) {});

      expect(await forbidden, '__no-forbidden__');
    },
  );

  test(
    '목표 5 — 학부모(parentA1)가 연결되지 않은 학생(학생 3)의 회차 채널을 '
    '구독하면 forbiddenSubscriptions 에 그 목적지가 실린다 (위 시험과 짝을 '
    '이루는 부정 확인 — "붙는다"만 보여서는 아무 학생이나 보이는 것과 '
    '구별되지 않는다)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final storage = await login('parentA1', 'p3-parent-unlinked');
      final client = BaraedaWebSocketClient(url: wsUrl, tokenStorage: storage);
      addTearDown(client.dispose);

      client.connect();
      await client.connectionState
          .firstWhere((s) => s == WsConnectionState.connected)
          .timeout(const Duration(seconds: 10));

      final forbidden = client.forbiddenSubscriptions
          .firstWhere((d) => d == WsChannel.studentRun('3'))
          .timeout(const Duration(seconds: 10));

      client.subscribe(WsChannel.studentRun('3'), (_) {});

      expect(await forbidden, WsChannel.studentRun('3'));
    },
  );

  test(
    '목표 5 — 학생(studentA4) 본인이 자기 회차 채널(학생 4)을 구독하면 '
    '거부되지 않는다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final storage = await login('studentA4', 'p3-student-self');
      final client = BaraedaWebSocketClient(url: wsUrl, tokenStorage: storage);
      addTearDown(client.dispose);

      client.connect();
      await client.connectionState
          .firstWhere((s) => s == WsConnectionState.connected)
          .timeout(const Duration(seconds: 10));

      final forbidden = client.forbiddenSubscriptions
          .firstWhere((d) => d == WsChannel.studentRun('4'))
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () => '__no-forbidden__',
          );

      client.subscribe(WsChannel.studentRun('4'), (_) {});

      expect(await forbidden, '__no-forbidden__');
    },
  );

  test(
    '목표 5 — 학생(studentA4)이 남의 회차 채널(학생 1)을 구독하면 거부된다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final storage = await login('studentA4', 'p3-student-other');
      final client = BaraedaWebSocketClient(url: wsUrl, tokenStorage: storage);
      addTearDown(client.dispose);

      client.connect();
      await client.connectionState
          .firstWhere((s) => s == WsConnectionState.connected)
          .timeout(const Duration(seconds: 10));

      final forbidden = client.forbiddenSubscriptions
          .firstWhere((d) => d == WsChannel.studentRun('1'))
          .timeout(const Duration(seconds: 10));

      client.subscribe(WsChannel.studentRun('1'), (_) {});

      expect(await forbidden, WsChannel.studentRun('1'));
    },
  );
}
