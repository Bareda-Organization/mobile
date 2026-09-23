@Tags(['real_backend'])
library;

import 'dart:io';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/delay/data/delay_api.dart';
import 'package:manager_app/features/delay/data/delay_repository_impl.dart';
import 'package:manager_app/features/delay/data/models/delay_request.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import '../support/real_backend_target.dart';

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

/// 실제 백엔드를 때리는 계약 시험 — R1 목표 3항(자기 포트의 실제 백엔드로
/// 1회 이상 호출). 시드 계정 `driverA1`·`escortA1`/`password`(BRIEF-m1.md
/// §5). 대상 서버는 `ApiConstants.baseUrl`(`--dart-define=API_BASE_URL`)이
/// 정한다 — `auto_login_test.dart` 와 같은 이유로 하드코딩하지 않는다.
///
/// §4.1(`ManagerRunApi.fetchRuns`)·§4.2(`RosterApi.fetchRoster`)는 한때 이
/// 백엔드가 스펙과 어긋난 응답을 내려 프로덕션 클라이언트 코드를 그대로
/// 통과시킬 수 없었다(보고서 참고 — F3 R2 B1 좌석이 서버를 고쳤다):
///
/// 1. `GET /manager/runs` 의 `data` 는 스펙(§4.1)대로 `{items:[...]}` 다.
/// 2. `run_id`·`stop_id`·`rider_id`·`student_id` 는 스펙(§1.1 "식별자는
///    서버 발급 문자열")대로 전부 문자열이다.
///
/// 그래서 이 파일은 그 두 엔드포인트에도 프로덕션 모델(`ManagerRunApi`·
/// `RosterApi`)을 그대로 쓸 수 있지만, "백엔드가 실제로 응답하는가"(목표
/// 3항)와 "그 응답의 실제 모양이 스펙과 맞는가"를 함께 확인하기 위해 계속
/// 원재료 `Dio` 로 직접 호출해 JSON 형태를 눈으로 본다. 클라이언트 모델
/// 파싱을 통과하는 §4.9(지연 알림, ID 필드가 없어 이 결함의 영향을 받지
/// 않았다)는 실제 프로덕션 코드(`DelayApi`+`DelayRepositoryImpl`+
/// `guardDio`)로 끝까지 호출한다.
void main() {
  final baseUrl = requireRealBackendBaseUrl();
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
    // F5 M3 목표 — 아래 §4.2 는 confirmed 회차가 최소 1개 있어야 하는데,
    // `real_backend_manager_endpoints_test.dart` 의 §4.4 가 시각이 맞지
    // 않으면 그 회차(run2)를 moving 으로 영구히 옮겨 버린다. 어느 파일이
    // 먼저 실행되는지 고정할 수 없어(파일 탐색 순서) 이 파일도 같은 확인을
    // 반복한다 — 상세 이유는 real_backend_target.dart 의 함수 주석 참고.
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

  // FE-R2 목표 12 — 이 시험은 "목록 엔드포인트가 응답하고 스펙대로 생겼는가"
  // 만 본다. 회차 상태(run_status)는 일부러 보지 않는다 — 그것은 §4.2 가
  // 전담한다(겹침이 아니라 계층: 이 시험은 모양, §4.2 는 그 안의 상태값).
  // `runs, isNotEmpty` 만으로는 전 회차가 idle 이어도 통과하지만, 그것은
  // 이 시험의 책임이 아니다 — status 를 검사하려는 시도는 §4.2 와 같은
  // 것을 두 번 확인하는 중복이 된다.
  test(
    '§4.1 — 기사 로그인 후 GET /manager/runs 를 실제로 호출해 응답을 받는다 '
    '(원재료 dio — 이유는 파일 주석 참고). 응답이 스펙대로 items[] 로 '
    '감싸져 있고 run_id 가 문자열인 것도 이 자리에서 함께 확인한다 — '
    'run_status 값 자체는 §4.2 가 전담하므로 여기서는 보지 않는다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
        return;
      }

      final (:auth, :dio) = buildClient();
      await auth.login(loginId: 'driverA1', password: 'password');

      final response = await dio.get<dynamic>('/manager/runs');

      expect(response.statusCode, 200);
      // §4.1 — data 는 배열이 아니라 items[] 를 담은 객체다.
      expect(
        response.data,
        isA<Map<String, dynamic>>(),
        reason: 'API_SPEC §4.1 은 data 를 {items:[...]} 로 요구한다',
      );
      final runs = ((response.data as Map<String, dynamic>)['items'] as List)
          .cast<Map<String, dynamic>>();
      expect(runs, isNotEmpty);
      // §1.1 — 식별자는 서버 발급 문자열이다.
      expect(
        runs.first['run_id'],
        isA<String>(),
        reason: 'API_SPEC §4.1·§1.1 은 run_id: string 을 요구한다',
      );
    },
  );

  test(
    '§4.2 — GET /runs/{runId}/roster 를 실제로 호출해 응답을 받는다 (원재료 dio) — '
    'run_id 는 이 시험 안에서 GET /manager/runs 로 매번 새로 찾는다. 이 회차의 '
    'confirmed 여부는 시드의 상대 시각(출발 30분 전 확정)이 실제 시계 경과에 따라 '
    '바뀌므로 고정값을 박으면 시간이 지나면서 idle 로 넘어가 깨진다. '
    'FE-R2 목표 12 — 이 시험은 §4.1 이 일부러 보지 않는 run_status 를 전담해서 '
    '검사한다: confirmed 상태인 회차가 하나도 없으면(= BE-R1 이 고친 결함이 다시 '
    '나면) 아래 expect 가 그 자리에서 실패해야 한다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
        return;
      }

      final (:auth, :dio) = buildClient();
      await auth.login(loginId: 'driverA1', password: 'password');

      final runsResponse = await dio.get<Map<String, dynamic>>(
        '/manager/runs',
      );
      final runs = (runsResponse.data!['items'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final confirmedRuns = runs
          .where((run) => run['run_status'] == 'confirmed')
          .toList();
      // §4.1 은 목록이 비어 있지 않은 것만 보고 통과하므로, "confirmed 가
      // 소실됐다(전부 idle)"는 여기서 명시적으로 잡지 않으면 아무도 안 잡는다.
      expect(
        confirmedRuns,
        isNotEmpty,
        reason:
            '확정(confirmed) 상태인 회차가 없다 — 시드 데이터의 상대 시각을 '
            '확인해야 한다',
      );
      final runId = confirmedRuns.first['run_id'] as String;

      final response = await dio.get<Map<String, dynamic>>(
        '/runs/$runId/roster',
      );

      expect(response.statusCode, 200);
      // §1.1 — 식별자는 서버 발급 문자열이다. run_id·stop_id·rider_id·
      // student_id 전부 String.
      expect(response.data!['run_id'], runId);
      final stops = (response.data!['stops'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(stops.first['stop_id'], isA<String>());
      final students = (stops.first['students'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(students.first['rider_id'], isA<String>());
      expect(students.first['student_id'], isA<String>());
    },
  );

  test(
    '§4.9 — 실제 지연 알림 전송(sendDelay) 을 동승자 계정으로 호출하면 '
    '진짜 업무 규칙 오류(RUN_NOT_MOVING)를 받는다 — DelayResult 에는 ID '
    '필드가 없어 위 결함의 영향을 받지 않으므로 프로덕션 코드 '
    '(DelayApi→DelayRepositoryImpl→guardDio) 를 그대로 끝까지 쓴다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
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
        markTestSkipped('환경 문제: 백엔드 미기동($baseUrl)');
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
