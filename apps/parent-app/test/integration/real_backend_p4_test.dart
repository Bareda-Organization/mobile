@Tags(['real_backend'])
library;

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/change_requests/data/change_request_api.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/runs/data/run_api.dart';
import 'package:parent_app/core/runs/domain/run_intent_result.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/students/data/student_api.dart';
import 'package:parent_app/features/child_link/data/link_api.dart';
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

/// `DioException` 이 실려 온 구조화 오류(`{"error":{"code":...}}`)를
/// 검사한다 — 이 코드베이스에 기존 관행이 없어(§3.6·§3.8 오류 경로를
/// 다루는 첫 시험 파일) 이 파일에서 새로 정한다.
Future<void> _expectApiError(
  Future<void> Function() action, {
  required int statusCode,
  required String errorCode,
}) async {
  try {
    await action();
    fail('DioException($errorCode) 를 기대했으나 예외가 발생하지 않았다');
  } on DioException catch (e) {
    expect(e.response?.statusCode, statusCode);
    final data = e.response?.data;
    expect(data, isA<Map<String, dynamic>>());
    final error = (data as Map<String, dynamic>)['error'];
    expect(error, isA<Map<String, dynamic>>());
    expect((error as Map<String, dynamic>)['code'], errorCode);
  }
}

/// `--dart-define=API_BASE_URL` 로 지정한 서버를 실제로 때리는 계약
/// 시험 — P 좌석이 담당한 §3.6(승하차 의사)·§3.8(변경 요청)·§3.4(연결
/// 코드 확인)의 예외 경로(`API_SPEC §1.6` 3구간 규칙)를 실제 응답으로
/// 재현한다. 서버가 안 떠 있으면 `setUpAll` 헬스체크가 전체를 환경
/// 문제로 건너뛴다(`real_backend_p1_test.dart` 와 같은 구조).
///
/// 시드(`V2__seed_data.sql`) 기준 회차 상태 —
/// - run 6(학생 1, academy1, idle, 출발 4시간 뒤) — ①구간 전용 시나리오.
///   run 1 과 달리 다른 시험이 건드리지 않아 반복 실행 시 상태가
///   깨끗하다.
/// - run 3(학생 1, moving, 출발 10분 전 시작) — 상태 기반으로 ③구간에
///   고정(`ChangeWindowPolicy.segmentOf` — MOVING/FINISHED 는 시각과
///   무관하게 CLOSED). 시간이 흘러도 값이 변하지 않아 반복 가능하다.
/// - run 2(학생 1) — ②구간(`confirm_at` 통과, 출발 20분 전). 시드
///   `boarding_intent(1, run=2, student=1, change_used_count=0)` 로
///   할당량이 남아 있다 — 이 시험이 첫 소진 기회일 수도, 이미 다른
///   실행에서 소진했을 수도 있어 적응형으로 판정한다(Test C).
/// - run 2(학생 4) — 같은 ②구간이지만 시드
///   `boarding_intent(2, run=2, student=4, change_used_count=1)` 로
///   **이미 소진된 채 고정**돼 있다 — student 1 의 할당량과 공유되지
///   않는 별도 행이라 Test C 와 절대 간섭하지 않고, 항상 결정적으로
///   `CHANGE_LIMIT_REACHED` 를 재현한다(Test F).
///
/// §3.6 과 §3.8 은 `BoardingIntentCommandService`/`ChangeRequestCommandService`
/// 양쪽 다 같은 `boarding_intent.change_used_count` 행을
/// `findOrCreateIntent(runId, studentId)` 로 공유한다 — 그래서 Test C(학생
/// 1)와 Test F(학생 4)를 서로 다른 학생으로 갈라 두었다.
///
/// §3.7 PATCH(주소 갱신)와 §3.8 `type=relocate` 는 이 환경에서 다루지
/// 않는다 — 실측 결과 `:8133` 백엔드가 실제 Naver 지오코딩 클라이언트로
/// 떠 있고, 그 클라이언트가 이 환경에서 네트워크에 닿지 못해 임의의
/// 주소에 대해 항상 `503 ADDRESS_VERIFICATION_UNAVAILABLE` 을 반환한다
/// (3회 반복 확인). 실제 백엔드·실제 외부 의존이 존재하되 그 의존이
/// 도달 불가한 환경 제약이며 코드 결함이 아니다 — 보고서에 범위
/// 제외로 남긴다.
void main() {
  final baseUrl = requireRealBackendBaseUrl();
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
    '목표 — §3.6 ①구간(run6/학생1)이 승하차 의사를 즉시 반영한다 '
    '(반복 실행 가능)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final parent = buildClientFor('p4-a-parent');
      await parent.auth.login(loginId: 'parentA1', password: 'password');
      final students = await StudentApi(dio: parent.dio).getMyStudents();
      final chulsoo = students.firstWhere((s) => s.name == '김철수');
      final runApi = RunApi(dio: parent.dio);

      final off = await runApi.updateIntent(
        chulsoo.studentId,
        '6',
        riding: false,
      );
      expect(off.result, RunIntentApplyResult.applied);
      expect(off.riding, isFalse);
      expect(off.riderStatus, RiderStatus.absent);

      final on = await runApi.updateIntent(
        chulsoo.studentId,
        '6',
        riding: true,
      );
      expect(on.result, RunIntentApplyResult.applied);
      expect(on.riding, isTrue);
      expect(on.riderStatus, RiderStatus.waiting);
    },
  );

  test(
    '목표 — §3.6 ③구간(run3/학생1)에서 riding=true 는 항상 '
    'CHANGE_WINDOW_CLOSED 를 반환한다 (상태 기반 CLOSED, 반복 가능)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final parent = buildClientFor('p4-b-parent');
      await parent.auth.login(loginId: 'parentA1', password: 'password');
      final students = await StudentApi(dio: parent.dio).getMyStudents();
      final chulsoo = students.firstWhere((s) => s.name == '김철수');
      final runApi = RunApi(dio: parent.dio);

      await _expectApiError(
        () => runApi.updateIntent(chulsoo.studentId, '3', riding: true),
        statusCode: 403,
        errorCode: 'CHANGE_WINDOW_CLOSED',
      );
    },
  );

  test(
    '목표 — §3.6 ②구간(run2/학생1)의 할당량 소진 시 '
    'CHANGE_LIMIT_REACHED 를 반환한다 (적응형 — 소진 여부에 무관하게 '
    '건너뛰지 않는다)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final parent = buildClientFor('p4-c-parent');
      await parent.auth.login(loginId: 'parentA1', password: 'password');
      final students = await StudentApi(dio: parent.dio).getMyStudents();
      final chulsoo = students.firstWhere((s) => s.name == '김철수');
      final runApi = RunApi(dio: parent.dio);

      try {
        final result = await runApi.updateIntent(
          chulsoo.studentId,
          '2',
          riding: false,
        );
        // 첫 호출에서 아직 할당량이 남아 있었다 — ②구간이므로 반드시
        // 승인 대기여야 하고, 다음 호출은 소진돼 반드시 실패해야 한다.
        expect(result.result, RunIntentApplyResult.pendingApproval);

        await _expectApiError(
          () => runApi.updateIntent(chulsoo.studentId, '2', riding: false),
          statusCode: 403,
          errorCode: 'CHANGE_LIMIT_REACHED',
        );
      } on DioException catch (e) {
        // 이전 실행에서 이미 할당량을 소진해 첫 호출부터 실패한 경우.
        expect(e.response?.statusCode, 403);
        final error = (e.response?.data as Map<String, dynamic>)['error'];
        expect((error as Map<String, dynamic>)['code'], 'CHANGE_LIMIT_REACHED');
      }
    },
  );

  test(
    '목표 — §3.8 ①구간(run6/학생1/type=cancel)이 즉시 반영된다 '
    '(반복 실행 가능 — 감사 이력만 늘어난다)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final parent = buildClientFor('p4-d-parent');
      await parent.auth.login(loginId: 'parentA1', password: 'password');
      final students = await StudentApi(dio: parent.dio).getMyStudents();
      final chulsoo = students.firstWhere((s) => s.name == '김철수');
      final changeApi = ChangeRequestApi(dio: parent.dio);

      final result = await changeApi.createChangeRequest(
        chulsoo.studentId,
        type: ChangeRequestType.cancel,
        runId: '6',
      );
      expect(result.status, ChangeRequestStatus.approved);
      expect(result.result, 'applied');
    },
  );

  test(
    '목표 — §3.8 ③구간(run3/학생1/type=cancel)은 CHANGE_WINDOW_CLOSED 를 '
    '반환한다 (type 과 무관하게 상태 기반 CLOSED, 반복 가능)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final parent = buildClientFor('p4-e-parent');
      await parent.auth.login(loginId: 'parentA1', password: 'password');
      final students = await StudentApi(dio: parent.dio).getMyStudents();
      final chulsoo = students.firstWhere((s) => s.name == '김철수');
      final changeApi = ChangeRequestApi(dio: parent.dio);

      await _expectApiError(
        () => changeApi.createChangeRequest(
          chulsoo.studentId,
          type: ChangeRequestType.cancel,
          runId: '3',
        ),
        statusCode: 403,
        errorCode: 'CHANGE_WINDOW_CLOSED',
      );
    },
  );

  test(
    '목표 — §3.8 ②구간(run2/학생4/parentA2/type=cancel)은 시드가 이미 '
    '소진해 둔 할당량 때문에 항상 CHANGE_LIMIT_REACHED 를 반환한다 '
    '(결정적 — Test C 의 학생1 할당량과 별도 행이라 간섭하지 않는다)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final parent = buildClientFor('p4-f-parent');
      await parent.auth.login(loginId: 'parentA2', password: 'password');
      final students = await StudentApi(dio: parent.dio).getMyStudents();
      final haneul = students.firstWhere((s) => s.name == '이하늘');
      final changeApi = ChangeRequestApi(dio: parent.dio);

      await _expectApiError(
        () => changeApi.createChangeRequest(
          haneul.studentId,
          type: ChangeRequestType.cancel,
          runId: '2',
        ),
        statusCode: 403,
        errorCode: 'CHANGE_LIMIT_REACHED',
      );
    },
  );

  test(
    '목표 — §3.4 잘못된 연결 코드는 LINK_CODE_INVALID 를 반환한다 '
    '(상태를 만들지 않아 반복 가능)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final parent = buildClientFor('p4-g-parent');
      await parent.auth.login(loginId: 'parentA1', password: 'password');
      final linkApi = LinkApi(dio: parent.dio);

      await _expectApiError(
        () => linkApi.confirmLink('ZZZZZZ-존재하지-않음'),
        statusCode: 403,
        errorCode: 'LINK_CODE_INVALID',
      );
    },
  );
}
