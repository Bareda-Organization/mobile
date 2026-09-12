import 'dart:io';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/constants/api_constants.dart';
import 'package:manager_app/features/emergency/data/emergency_api.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_request.dart';
import 'package:manager_app/features/emergency/data/models/emergency_type.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// `real_backend_emergency_test.dart` 와 같은 대역 — 진짜 소켓 스토리지 대신
// 메모리에만 담는다.
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

/// BE-R1 수정 라운드 `FIX-EM` — §4.15 목록 응답의 `emergency_id` 가 서버에서
/// 원시 숫자로 나가면 `EmergencyItem.fromJson` 의 `json['emergency_id'] as
/// String` 캐스팅이 그 자리에서 예외를 던진다. "필드가 있다" 를 확인하는
/// 것으로는 이 사고를 못 잡는다 — 필드는 항상 있고, 타입만 틀렸었다.
///
/// `real_backend_emergency_test.dart` 와 같은 패턴으로 `EmergencyApi.raise`→
/// `EmergencyApi.list`→`EmergencyApi.cancel` 을 프로덕션 코드 그대로 실
/// 서버(포트는 `API_BASE_URL` dart-define, 이 회차는 8095·DB
/// `schoolbus_fixem`)에 붙여, 목록이 비어 있지 않은 상태에서 파싱이 예외
/// 없이 끝나는지 직접 확인한다.
void main() {
  const baseUrl = ApiConstants.baseUrl;
  late bool backendReachable;

  setUpAll(() async {
    // widget test 바인딩이 HttpOverrides.global 을 항상 400 을 주는 대역으로
    // 바꿔 두므로(auto_login_test.dart 와 같은 함정), 이 파일이 도는 동안만
    // 끈다.
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

  ({AuthApi auth, Dio dio}) buildClient() {
    FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
    final storage = TokenStorage(
      accessTokenKey: 'it-list-access',
      refreshTokenKey: 'it-list-refresh',
    );
    final client = ApiClient(tokenStorage: storage, baseUrl: baseUrl);
    final auth = AuthApi(dio: client.dio, tokenStorage: storage);
    return (auth: auth, dio: client.dio);
  }

  test(
    '§4.15 — 발신 직후 목록을 조회하면 비어 있지 않은 items 가 예외 없이 '
    '파싱되고, 그 emergency_id 로 취소(§4.14 DELETE)까지 이어진다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
        return;
      }

      final (:auth, :dio) = buildClient();
      await auth.login(loginId: 'driverA1', password: 'password');

      final api = EmergencyApi(dio: dio);
      final raised = await api.raise(
        runId: '1',
        request: EmergencyRaiseRequest(
          type: EmergencyType.accident,
          clientKey: IdempotencyKeys.generate(),
        ),
      );

      // 이 호출이 예외 없이 끝나는 것 자체가 검사다 — emergency_id 가
      // 숫자로 오면 EmergencyItem.fromJson 의 `as String` 캐스팅이 여기서
      // 던진다.
      final list = await api.list(runId: '1');

      expect(list.items, isNotEmpty);
      final item = list.items.firstWhere(
        (i) => i.emergencyId == raised.emergencyId,
        orElse: () => throw StateError(
          '방금 발신한 emergency_id(${raised.emergencyId})가 목록에 없다',
        ),
      );
      expect(item.emergencyId, raised.emergencyId);
      expect(item.canceledAt, isNull);

      // 목록에서 받은 emergency_id 를 그대로 취소 URL 에 넣는다 — 발신 →
      // 목록 → 취소가 한 값으로 이어지는지가 이 시험의 나머지 절반이다.
      await api.cancel(runId: '1', emergencyId: item.emergencyId);
    },
  );
}
