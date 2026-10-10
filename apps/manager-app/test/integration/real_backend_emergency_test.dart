@Tags(['real_backend'])
library;

import 'dart:io';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/emergency/data/emergency_api.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_request.dart';
import 'package:manager_app/features/emergency/data/models/emergency_type.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import '../support/real_backend_target.dart';

// `real_backend_run_flow_test.dart` 와 같은 대역 — 진짜 소켓 스토리지 대신
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

/// BE-R1 목표 1 후속 라운드 — "발신 후 취소 버튼이 뜬다" 를 위젯 시험(가짜
/// 저장소, `emergency_screen_test.dart`)만으로 확인한 것은 목표의 앱 동작
/// 조건을 채우지 못한다는 지적을 받아 추가한 시험이다.
///
/// `emergency_screen_test.dart` 는 `EmergencyRaiseResult` 를 코드에서 직접
/// 만들어 주입하므로 `EmergencyRaiseResult.fromJson` — 실 서버 응답을 그
/// 모델로 바꾸는 자리 — 을 한 번도 통과하지 않는다. 이 파일은
/// `real_backend_run_flow_test.dart` 와 같은 패턴으로 `EmergencyApi` 를
/// 원재료가 아니라 **프로덕션 코드 그대로**(`EmergencyApi.raise`→
/// `EmergencyRaiseResult.fromJson`) 실 서버(포트는 `ApiConstants.baseUrl`,
/// 이 회차는 8081·DB `schoolbus_ber1em`)에 붙여 호출하고, 화면이 취소
/// 버튼을 보여줄지 판단하는 것과 같은 조건(`now.isBefore(cancelableUntil)`,
/// `emergency_screen.dart` 참고)을 그 실제 파싱 결과로 직접 계산한다.
///
/// 시드 `driverA1`(BRIEF-em.md 계정)은 회차 1(idle)·2(confirmed)·7(confirmed)
/// 에 driver 로 배치돼 있다(`assignment` 시드 실측). **발신은 확정
/// (confirmed) 이후 회차에만 받는다**(API_SPEC §4.14 "발신 시점" · BR-109)
/// — 회차 1(idle)로 부르면 `assertAssignedDriverOrEscort` 는 통과해도
/// `EmergencyCommandService.raise` 가 곧바로 `409 RUN_NOT_CONFIRMED` 로
/// 거부한다. 성공 경로는 회차 2 대신 7(confirmed, 내일 출발이라 재구성
/// 없이도 오래 살아 있다 — 회차 2 는 오늘 날짜라 자정 경계 위험이 있다)로
/// 발신하고, 확정 전 회차 거부는 아래 별도 시험이 회차 1로 재현한다.
void main() {
  final baseUrl = requireRealBackendBaseUrl();
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
    // BR-109 시험은 시드의 idle 회차(run 1)를 요구한다 — 서버의 확정 배치가 시드 적용 +2.5h 에
    // 그 회차를 confirmed 로 옮기므로, 서버를 오래 켜 둔 뒤에는 필요할 때만 시드를 되돌린다
    // (real_backend_target.dart 의 함수 주석 ③). 되돌리지 않으면 서버가 발신을 받아 409 대신
    // 200 이 오고 신고 행이 쌓인다.
    if (backendReachable) {
      await ensureManagerSeedIsSafeForTiming(baseUrl);
    }
  });

  ({AuthApi auth, Dio dio}) buildClient() {
    FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
    final storage = TokenStorage(
      accessTokenKey: 'it-access',
      refreshTokenKey: 'it-refresh',
    );
    final client = ApiClient(tokenStorage: storage, baseUrl: baseUrl);
    final auth = AuthApi(dio: client.dio, tokenStorage: storage);
    return (auth: auth, dio: client.dio);
  }

  test(
    '§4.14 — 실 서버로 비상 알림을 발신하면 emergency_id·raised_at· '
    'cancelable_until·notified 4항이 예외 없이 파싱되고, 그 결과가 화면의 '
    '취소 버튼 노출 조건(now.isBefore(cancelableUntil))을 즉시 만족한다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
        return;
      }

      final (:auth, :dio) = buildClient();
      await auth.login(loginId: 'driverA1', password: 'password');

      final api = EmergencyApi(dio: dio);
      final result = await api.raise(
        runId: '7',
        request: EmergencyRaiseRequest(
          type: EmergencyType.accident,
          clientKey: IdempotencyKeys.generate(),
        ),
      );

      // emergency_id 는 서버가 Long 을 문자열로 내려준다(§1.1) — 파싱이
      // String 캐스트에서 예외를 던지지 않았다는 것 자체가 이 검사다.
      expect(result.emergencyId, isNotEmpty);
      expect(int.tryParse(result.emergencyId), isNotNull);
      expect(result.notified, greaterThanOrEqualTo(0));
      expect(
        result.cancelableUntil.isAfter(result.raisedAt),
        isTrue,
        reason: '취소 가능 창은 발신 시각 이후여야 한다',
      );

      // emergency_screen.dart 의 취소 버튼 노출 조건과 같은 식이다 — 실
      // 서버가 준 값을 그대로 넣었을 때 화면이 버튼을 보여줄지를 여기서
      // 직접 계산한다(위젯 시험은 이 값을 가짜 저장소로 주입해 그 뒤
      // 렌더링만 검증한다 — 두 시험이 합쳐야 "취소 버튼이 뜬다" 전체가
      // 실측된다).
      final now = DateTime.now().toUtc();
      expect(
        now.isBefore(result.cancelableUntil),
        isTrue,
        reason: '발신 직후에는 취소 버튼이 보여야 한다',
      );

      // 취소도 프로덕션 코드로 끝까지 확인한다(§4.14 취소, 204) — 뒤에 남는
      // 신고 행이 다음 실행의 시드 상태를 더럽히지 않게 한다.
      await api.cancel(runId: '7', emergencyId: result.emergencyId);
    },
  );

  // BR-109 — 확정 전(idle) 회차는 발신을 받지 않는다(§4.14 · Ruling 357).
  // 회차 1 은 시드 기준 그대로 idle 이고 driverA1 이 배치돼 있어, 배치
  // 인가(assertAssignedDriverOrEscort)는 통과하고 상태 검사에서만 막히는지
  // 를 구분해 확인한다. 단 시드 적용 +2.5h 가 지나면 확정 배치가 이 회차를
  // confirmed 로 옮기므로 setUpAll 이 필요할 때 시드를 되돌린다.
  test(
    'RUN_NOT_CONFIRMED — 확정 전(idle) 회차로 비상 알림을 발신하면 409 로 '
    '거부된다(BR-109)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
        return;
      }

      final (:auth, :dio) = buildClient();
      await auth.login(loginId: 'driverA1', password: 'password');

      final api = EmergencyApi(dio: dio);
      try {
        await api.raise(
          runId: '1',
          request: EmergencyRaiseRequest(
            type: EmergencyType.accident,
            clientKey: IdempotencyKeys.generate(),
          ),
        );
        fail('idle 회차로 발신했는데 409 가 아니었다');
      } on DioException catch (e) {
        expect(e.response?.statusCode, 409);
        final data = e.response?.data as Map<String, dynamic>?;
        final error = data?['error'] as Map<String, dynamic>?;
        expect(error?['code'], 'RUN_NOT_CONFIRMED');
      }
    },
  );
}
