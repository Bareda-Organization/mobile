@Tags(['real_backend'])
library;

import 'package:baraeda_core/auth/auth_api.dart';
import 'package:baraeda_core/network/api_client.dart';
import 'package:baraeda_core/storage/token_storage.dart';
import 'package:baraeda_core/websocket/ws_channel.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:web_socket/web_socket.dart';
import '../support/real_backend_target.dart';

// `test/integration/real_backend_auth_test.dart` 와 같은 가짜.
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

/// 완료 조건 2 를 `BaraedaWebSocketClient`/`stomp_dart_client` 를 거치지
/// 않고 **원시 WebSocket 프레임 수준**에서 확인한다 —
/// `stomp_dart_client` 의 공개 API 는 close code 를 노출하지 않으므로
/// (`onWebSocketDone` 콜백에 인자가 없다), `4403` 그 자체를 보려면
/// `package:web_socket` 으로 직접 CONNECT + SUBSCRIBE 텍스트 프레임을
/// 만들어 보내야 한다.
void main() {
  final apiBaseUrl = requireRealBackendBaseUrl();
  final wsUri = (() {
    final uri = Uri.parse(apiBaseUrl);
    return uri.replace(scheme: 'ws', path: '/ws/location');
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

  Future<String> loginParentA1AccessToken() async {
    FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
    final storage = TokenStorage(
      accessTokenKey: 'ws-raw-it-access',
      refreshTokenKey: 'ws-raw-it-refresh',
    );
    final client = ApiClient(tokenStorage: storage, baseUrl: apiBaseUrl);
    final auth = AuthApi(dio: client.dio, tokenStorage: storage);
    await auth.login(loginId: 'parentA1', password: 'password');
    final token = await storage.readAccessToken();
    return token!;
  }

  test(
    '완료 조건 2 — 권한 없는 채널을 SUBSCRIBE 하면 서버가 원시 WebSocket '
    'close code 4403 으로 연결을 닫는다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $apiBaseUrl 백엔드 미기동');
        return;
      }
      final token = await loginParentA1AccessToken();
      final socket = await WebSocket.connect(wsUri);
      addTearDown(() async {
        try {
          await socket.close();
        } on WebSocketException {
          // 이미 서버가 닫았으면 close() 가 예외를 던진다 — 시험 종료
          // 정리 단계라 무시한다.
        }
      });

      final closeFuture = socket.events
          .where((e) => e is CloseReceived)
          .cast<CloseReceived>()
          .first
          .timeout(const Duration(seconds: 10));

      // STOMP 1.2 CONNECT 프레임 — 널 문자(`\x00`)로 끝난다.
      socket
        ..sendText(
          'CONNECT\n'
          'accept-version:1.2\n'
          'host:localhost\n'
          'Authorization:Bearer $token\n'
          '\n'
          '\x00',
        )
        // parentA1(학부모)은 매니저 채널(기사·동승자 전용)에 권한이 없다 —
        // CONNECTED 응답을 기다리지 않고 바로 SUBSCRIBE 를 보내도 서버는
        // 프레임 순서대로 처리하므로 문제 없다.
        ..sendText(
          'SUBSCRIBE\n'
          'id:sub-0\n'
          'destination:${WsChannel.managerRun('1')}\n'
          '\n'
          '\x00',
        );

      final close = await closeFuture;
      expect(close.code, 4403);
    },
  );
}
