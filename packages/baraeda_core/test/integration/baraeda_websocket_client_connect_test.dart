@Tags(['real_backend'])
library;

import 'package:baraeda_core/auth/auth_api.dart';
import 'package:baraeda_core/network/api_client.dart';
import 'package:baraeda_core/storage/token_storage.dart';
import 'package:baraeda_core/websocket/baraeda_websocket_client.dart';
import 'package:baraeda_core/websocket/ws_backoff_policy.dart';
import 'package:baraeda_core/websocket/ws_channel.dart';
import 'package:baraeda_core/websocket/ws_connection_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import '../support/real_backend_target.dart';

// `test/integration/real_backend_auth_test.dart` 와 같은 구조의 가짜 —
// 이 시험도 실 시크릿 스토리지 플러그인 없이 도는 실 백엔드 계약 시험이다.
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

/// `/ws/location` 에 실제로 붙는 계약 시험 — 완료 조건 1·2. `--dart-define`
/// 으로 REST 베이스 URL 을 받아 그 호스트·포트를 그대로 WS 로 바꿔 쓴다
/// (`real_backend_auth_test.dart` 와 같은 근거 — 리터럴 포트를 박으면
/// 격리 포트(8140)를 줘도 이 파일이 무시한다).
void main() {
  final apiBaseUrl = requireRealBackendBaseUrl();
  // `/api/v1` 접미사를 떼고 스킴을 ws 로 바꾼 뒤 `/ws/location` 을 붙인다.
  final wsUrl = (() {
    final uri = Uri.parse(apiBaseUrl);
    return uri
        .replace(scheme: 'ws', path: '/ws/location')
        .toString();
  })();

  late bool backendReachable;

  setUpAll(() async {
    final probe = Dio(BaseOptions(baseUrl: apiBaseUrl));
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

  /// `parentA1` 으로 실제 로그인해 토큰을 저장소에 심어 둔 `TokenStorage`
  /// 를 돌려준다 — `real_backend_auth_test.dart` 의 `driverBlocked` 처럼
  /// 상태를 바꾸지 않는 읽기 전용 로그인이라 여러 시험이 나눠 써도 안전하다
  /// (로그인 자체는 실패 카운터를 증가시키지 않는다 — 성공이므로).
  Future<TokenStorage> loginParentA1() async {
    FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
    final storage = TokenStorage(
      accessTokenKey: 'ws-it-access',
      refreshTokenKey: 'ws-it-refresh',
    );
    final client = ApiClient(tokenStorage: storage, baseUrl: apiBaseUrl);
    final auth = AuthApi(dio: client.dio, tokenStorage: storage);
    await auth.login(loginId: 'parentA1', password: 'password');
    return storage;
  }

  test(
    '완료 조건 1 — 유효한 토큰으로 CONNECT 하면 connected 상태에 도달한다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $apiBaseUrl 백엔드 미기동');
        return;
      }
      final storage = await loginParentA1();
      final client = BaraedaWebSocketClient(
        url: wsUrl,
        tokenStorage: storage,
      );
      addTearDown(client.dispose);

      client.connect();

      final state = await client.connectionState
          .firstWhere(
            (s) =>
                s == WsConnectionState.connected ||
                s == WsConnectionState.gaveUp,
          )
          .timeout(const Duration(seconds: 10));

      expect(state, WsConnectionState.connected);
    },
  );

  test(
    '완료 조건 1 — 토큰 없이 CONNECT 하면 절대 connected 에 도달하지 않는다 '
    '(1번과 짝을 이루는 부정 확인 — "붙는다"만 보여서는 아무나 붙는 것과 '
    '구별되지 않는다)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $apiBaseUrl 백엔드 미기동');
        return;
      }
      FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
      // 토큰을 아예 저장하지 않은 빈 저장소 — readAccessToken() 이 null 을
      // 돌려주므로 CONNECT 프레임에 Authorization 헤더 자체가 실리지 않는다.
      final emptyStorage = TokenStorage(
        accessTokenKey: 'ws-it-no-token-access',
        refreshTokenKey: 'ws-it-no-token-refresh',
      );
      final client = BaraedaWebSocketClient(
        url: wsUrl,
        tokenStorage: emptyStorage,
        // 재시도가 몇 번이고 전부 거부될 것이므로 상한을 낮게 잡아 시험이
        // 빨리 끝나게 한다 — 완료 조건 3(백오프)의 관심사가 아니다.
        backoffPolicy: const WsBackoffPolicy(
          initialDelay: Duration(milliseconds: 100),
          maxDelay: Duration(milliseconds: 200),
          maxAttempts: 2,
        ),
      );
      addTearDown(client.dispose);

      client.connect();

      // `StompAuthChannelInterceptor.authenticateConnect()` 가
      // `IllegalArgumentException` 을 던지면 소켓이 닫히고 재연결이
      // 돌다가 결국 포기한다 — connected 는 어느 시점에도 나타나지 않는다.
      final state = await client.connectionState
          .firstWhere((s) => s == WsConnectionState.gaveUp)
          .timeout(const Duration(seconds: 10));

      expect(state, WsConnectionState.gaveUp);
      expect(client.state, isNot(WsConnectionState.connected));
    },
  );

  test(
    '완료 조건 2 — 권한 없는 채널을 구독하면 STOMP ERROR(FORBIDDEN) 로 '
    '드러나 forbiddenSubscriptions 스트림에 실린다 (2단계 앱이 쓸 상위 API '
    '경로 — 원시 close code 4403 자체는 아래 raw 시험에서 별도로 확인한다)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $apiBaseUrl 백엔드 미기동');
        return;
      }
      final storage = await loginParentA1();
      final client = BaraedaWebSocketClient(
        url: wsUrl,
        tokenStorage: storage,
      );
      addTearDown(client.dispose);

      client.connect();
      await client.connectionState
          .firstWhere((s) => s == WsConnectionState.connected)
          .timeout(const Duration(seconds: 10));

      // parentA1 은 학부모 역할이라 매니저 채널(기사·동승자 전용)에는
      // 어떤 회차 id 를 넣어도 권한이 없다 — `StompAuthChannelInterceptor`
      // 의 `authorizeSubscribe()` 가 역할부터 걸러낸다.
      final forbidden = client.forbiddenSubscriptions
          .firstWhere((d) => d == WsChannel.managerRun('1'))
          .timeout(const Duration(seconds: 10));

      client.subscribe(WsChannel.managerRun('1'), (_) {});

      final destination = await forbidden;
      expect(destination, WsChannel.managerRun('1'));
    },
  );
}
