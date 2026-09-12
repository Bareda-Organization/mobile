import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/features/settings/data/notification_settings_api.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:uuid/uuid.dart';

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

/// `localhost:8082`(`schoolbus_p2`)를 실제로 때리는 계약 시험 — P2 게이트
/// 조건 ⑤. `real_backend_p1_test.dart` 가 담당한 P1 화면과 달리, 이 파일은
/// P2 라운드에서 새로 다룬 설정 4개 엔드포인트(§2.8·§2.9·§2.11·§3.14)를
/// 최소 1회씩 실제로 호출한다 — 지금까지는 위젯 시험의 가짜
/// 저장소·가짜 레포지토리로만 검증돼 있었고, 서버가 실제로 그 계약대로
/// 응답하는지는 확인된 적이 없었다.
///
/// **계정은 `parentA3`(account 7, 010-1000-0003)를 쓴다** —
/// `real_backend_p1_test.dart`·`auto_login_test.dart` 가 이미 `parentA1`·
/// `studentA4` 를 쓰고 있어, 같이 돌 때 계정을 공유하면 §2.8(비밀번호 변경 →
/// refresh 토큰 전량 무효화)이 다른 시험의 로그인 세션을 깨뜨린다
/// (`grep -rn "parentA2\|parentA3"` 로 이 시험 작성 시점에 다른 파일에서
/// 쓰지 않는 것을 확인).
///
/// **부수효과가 남는 호출(§2.8 비밀번호 변경·§2.11 단말 등록)은 시험
/// 안에서 원래 상태로 되돌린다** — 서버가 안 떠 있으면 `setUpAll`
/// 헬스체크가 전체를 환경 문제로 건너뛴다(`real_backend_p1_test.dart` 와
/// 같은 구조).
void main() {
  const baseUrl = 'http://localhost:8082/api/v1';
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

  ({Dio dio, AuthApi auth}) buildClientFor(String storagePrefix) {
    final storage = TokenStorage(
      accessTokenKey: '$storagePrefix-access',
      refreshTokenKey: '$storagePrefix-refresh',
    );
    final client = ApiClient(tokenStorage: storage, baseUrl: baseUrl);
    final auth = AuthApi(dio: client.dio, tokenStorage: storage);
    return (dio: client.dio, auth: auth);
  }

  test(
    '§2.9 — 등록된 전화번호로 인증코드 발송을 실제로 요청한다 (비인증)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: localhost:8082 백엔드 미기동');
        return;
      }
      // `verificationCode` 를 생략하면 SMS 발송 요청으로 처리된다(§2.9) —
      // 실제 SMS 연동이 없는 이 저장소에서 부작용 없이 계약만 확인 가능한
      // 유일한 호출 형태다.
      final client = buildClientFor('p2-recover');
      await client.auth.recover(type: 'login_id', phone: '010-1000-0003');
      // 예외 없이 끝나면 그것이 곧 계약 성공이다(§2.9 성공 응답은 본문이
      // 없다).
    },
  );

  test(
    'NTF-12 · §2.11 — 단말을 등록하고 해지까지 실제로 왕복한다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: localhost:8082 백엔드 미기동');
        return;
      }
      final client = buildClientFor('p2-device');
      await client.auth.login(loginId: 'parentA3', password: 'password');

      const deviceId = 'p2-gate-integration-device';
      final token = const Uuid().v4();

      final registerResult = await client.auth.registerDevice(
        DeviceRegistrationRequest(
          token: token,
          platform: 'android',
          deviceId: deviceId,
        ),
      );
      expect(registerResult.deviceId, deviceId);

      // 등록으로 남긴 행을 그대로 두지 않는다 — 수동 해지(§2.11 표의
      // "해지" 행)로 원상복구한다.
      await client.auth.unregisterDevice(token);
    },
  );

  test(
    'NTF-07 · §3.14 — 알림 설정을 조회·변경하고 원래 값으로 되돌린다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: localhost:8082 백엔드 미기동');
        return;
      }
      final client = buildClientFor('p2-notif');
      await client.auth.login(loginId: 'parentA3', password: 'password');
      final api = NotificationSettingsApi(dio: client.dio);

      final original = await api.getNotificationSettings();

      final flipped = original.copyWith(arrive: !original.arrive);
      final patched = await api.updateNotificationSettings(flipped);
      expect(patched.arrive, flipped.arrive);

      // 다음 실행에서도 같은 전제(원래 값)로 시작하도록 되돌린다.
      final restored = await api.updateNotificationSettings(original);
      expect(restored.arrive, original.arrive);
    },
  );

  test(
    'AUTH-07 · §2.8 — 비밀번호를 실제로 변경했다가 원래 값으로 되돌린다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: localhost:8082 백엔드 미기동');
        return;
      }
      const original = 'password';
      const temporary = 'p2GateTemp1';

      final client = buildClientFor('p2-password');
      await client.auth.login(loginId: 'parentA3', password: original);
      await client.auth.changePassword(
        currentPassword: original,
        newPassword: temporary,
      );

      // §2.8 은 성공 시 이 계정의 refresh 토큰을 전량 무효화한다 — 되돌리는
      // 호출은 새 비밀번호로 새로 로그인한 세션에서 해야 한다.
      final revertClient = buildClientFor('p2-password-revert');
      await revertClient.auth.login(loginId: 'parentA3', password: temporary);
      await revertClient.auth.changePassword(
        currentPassword: temporary,
        newPassword: original,
      );

      // 원래 비밀번호로 다시 로그인이 되는 것까지 확인해야 원상복구가
      // 실제로 끝났다고 말할 수 있다.
      final verifyClient = buildClientFor('p2-password-verify');
      final login = await verifyClient.auth.login(
        loginId: 'parentA3',
        password: original,
      );
      expect(login.accessToken, isNotEmpty);
    },
  );
}
