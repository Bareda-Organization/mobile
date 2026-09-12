import 'dart:io';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/delay/data/delay_api.dart';
import 'package:manager_app/features/delay/data/delay_repository_impl.dart';
import 'package:manager_app/features/delay/data/models/delay_request.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// `real_backend_auth_test.dart`(F2, baraeda_core) 와 같은 구조 — 진짜
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

/// `localhost:8083`(M1 전용 백엔드·`schoolbus_m1`)을 실제로 때리는 계약
/// 시험 — R1 목표 3항(자기 포트의 실제 백엔드로 1회 이상 호출). 시드 계정
/// `driverA1`·`escortA1`/`password`(BRIEF-m1.md §5). 이 DB 는 이 좌석만
/// 쓰므로 회차 상태를 실제로 바꿔도 된다.
///
/// ⚠ §4.1(`ManagerRunApi.fetchRuns`)·§4.2(`RosterApi.fetchRoster`)는 이
/// 백엔드 인스턴스의 실제 응답으로 재현되는 두 가지 결함 때문에 프로덕션
/// 클라이언트 코드를 그대로 통과시킬 수 없다 — 클라이언트 코드는
/// `API_SPEC.md` 대로 작성됐고 문제는 백엔드 쪽이다(보고서 참고):
///
/// 1. `GET /manager/runs` 의 `data` 가 스펙이 요구하는 `{items:[...]}` 가
///    아니라 **맨 배열**이다 — `ManagerRunApi.fetchRuns` 는 `items` 키를
///    찾다가 빈 목록을 반환하는 게 아니라 `response.data` 자체가
///    `Map<String,dynamic>` 캐스트에서 죽는다(실측: `type 'List<dynamic>'
///    is not a subtype of type 'Map<String, dynamic>?'`).
/// 2. `run_id`·`stop_id`·`rider_id`·`student_id` 가 스펙(`string`)과 달리
///    **정수**로 온다 — `RosterResponse.fromJson` 의 `json['run_id'] as
///    String` 이 `type 'int' is not a subtype of type 'String'` 로 죽는다.
///
/// 그래서 이 파일은 그 두 엔드포인트에는 **원재료 `Dio` 로 직접 호출**해
/// "백엔드가 실제로 응답하는가"(목표 3항)와 "그 응답의 실제 모양"(결함
/// 근거)만 확인하고, 클라이언트 모델 파싱을 통과하는 §4.9(지연 알림, ID
/// 필드가 없어 이 결함의 영향을 받지 않는다)는 실제 프로덕션 코드
/// (`DelayApi`+`DelayRepositoryImpl`+`guardDio`)로 끝까지 호출한다.
void main() {
  const baseUrl = 'http://localhost:8083/api/v1';
  late bool backendReachable;

  setUpAll(() async {
    // widget test 바인딩이 HttpOverrides.global 을 항상 400 을 주는 대역으로
    // 바꿔 두므로(F2 auto_login_test.dart 와 같은 함정), 이 파일이 도는 동안만
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
      accessTokenKey: 'it-access',
      refreshTokenKey: 'it-refresh',
    );
    final client = ApiClient(tokenStorage: storage, baseUrl: baseUrl);
    final auth = AuthApi(dio: client.dio, tokenStorage: storage);
    return (auth: auth, dio: client.dio);
  }

  test(
    '§4.1 — 기사 로그인 후 GET /manager/runs 를 실제로 호출해 응답을 받는다 '
    '(원재료 dio — 이유는 파일 주석 참고). 응답이 스펙의 items[] 래핑이 '
    '아니라 맨 배열인 것도 이 자리에서 함께 확인한다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: localhost:8083(schoolbus_m1) 백엔드 미기동');
        return;
      }

      final (:auth, :dio) = buildClient();
      await auth.login(loginId: 'driverA1', password: 'password');

      final response = await dio.get<dynamic>('/manager/runs');

      expect(response.statusCode, 200);
      // 결함 1 — 스펙(§4.1)은 `{items: [...]}` 를 요구하지만 실제로는
      // 봉투를 벗긴 `data` 자체가 List 다.
      expect(
        response.data,
        isA<List<dynamic>>(),
        reason:
            'API_SPEC §4.1 은 {items:[...]} 를 요구하는데 실제 백엔드는 '
            '맨 배열을 반환한다 — ManagerRunController.list 결함(보고서 참고)',
      );
      final runs = (response.data as List<dynamic>).cast<
        Map<String, dynamic>
      >();
      expect(runs, isNotEmpty);
      // 결함 2 — run_id 가 string 이 아니라 int.
      expect(
        runs.first['run_id'],
        isA<int>(),
        reason: 'API_SPEC §4.1 은 run_id: string 을 요구한다',
      );
    },
  );

  test(
    '§4.2 — GET /runs/1/roster 를 실제로 호출해 응답을 받는다 (원재료 dio) — '
    'run_id 는 curl 로 미리 확인한 값(1, driverA1 배정 회차)을 직접 넣는다'
    '(§4.1 이 맨 배열이라 목록에서 얻을 수 없다)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: localhost:8083(schoolbus_m1) 백엔드 미기동');
        return;
      }

      final (:auth, :dio) = buildClient();
      await auth.login(loginId: 'driverA1', password: 'password');

      final response = await dio.get<Map<String, dynamic>>('/runs/1/roster');

      expect(response.statusCode, 200);
      expect(response.data!['run_id'], 1);
      // 결함 2 의 두 번째 근거 — stop_id·rider_id·student_id 도 전부 int.
      final stops = (response.data!['stops'] as List<dynamic>).cast<
        Map<String, dynamic>
      >();
      expect(stops.first['stop_id'], isA<int>());
      final students = (stops.first['students'] as List<dynamic>).cast<
        Map<String, dynamic>
      >();
      expect(students.first['rider_id'], isA<int>());
      expect(students.first['student_id'], isA<int>());
    },
  );

  test(
    '§4.9 — 실제 지연 알림 전송(sendDelay) 을 동승자 계정으로 호출하면 '
    '진짜 업무 규칙 오류(RUN_NOT_MOVING)를 받는다 — DelayResult 에는 ID '
    '필드가 없어 위 결함의 영향을 받지 않으므로 프로덕션 코드 '
    '(DelayApi→DelayRepositoryImpl→guardDio) 를 그대로 끝까지 쓴다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: localhost:8083(schoolbus_m1) 백엔드 미기동');
        return;
      }

      final (:auth, :dio) = buildClient();
      // run 1 은 확정 상태(confirmed)라 §4.9 가 요구하는 "운행 중"이 아니다
      // — 동승자 권한 자체는 통과하고 상태 게이트에서 막히는 경로를 본다.
      await auth.login(loginId: 'escortA1', password: 'password');

      final repository = DelayRepositoryImpl(api: DelayApi(dio: dio));

      Failure? failure;
      try {
        await repository.sendDelay(
          runId: '1',
          request: const DelayRequest(
            minutes: 10,
            reason: DelayReason.traffic,
          ),
        );
      } on Failure catch (f) {
        failure = f;
      }

      expect(failure, isA<ApiFailure>());
      final apiFailure = failure! as ApiFailure;
      expect(apiFailure.statusCode, 409);
      expect(apiFailure.code, 'RUN_NOT_MOVING');
    },
  );

  test(
    '§4.9 — 기사 계정으로 호출하면 역할 게이트(ESCORT_ONLY)에서 막힌다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: localhost:8083(schoolbus_m1) 백엔드 미기동');
        return;
      }

      final (:auth, :dio) = buildClient();
      await auth.login(loginId: 'driverA1', password: 'password');

      final repository = DelayRepositoryImpl(api: DelayApi(dio: dio));

      Failure? failure;
      try {
        await repository.sendDelay(
          runId: '1',
          request: const DelayRequest(
            minutes: 10,
            reason: DelayReason.traffic,
          ),
        );
      } on Failure catch (f) {
        failure = f;
      }

      expect(failure, isA<ApiFailure>());
      final apiFailure = failure! as ApiFailure;
      expect(apiFailure.statusCode, 403);
      expect(apiFailure.code, 'ESCORT_ONLY');
    },
  );
}
