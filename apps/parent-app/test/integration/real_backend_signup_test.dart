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

/// `DioException` 이 실려 온 구조화 오류(`{"error":{"code":...}}`)를 검사한다
/// (`real_backend_p4_test.dart` 의 `_expectApiError` 와 같은 모양 — 이 파일은
/// 그 파일을 import 하지 않는다: private 헬퍼라 공유되지 않는다).
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

/// `--dart-define=API_BASE_URL` 로 지정한 서버를 실제로 때리는 계약 시험 —
/// `API_SPEC §2.1~§2.4`(가입 전 화면 4개 엔드포인트, `### ` 헤더 직접 확인:
/// 이 4절이 각 1개씩 정확히 4개 엔드포인트를 정의한다) 를 이번 라운드에
/// 새로 추가한다. FE-R3 목표 18 — 원래 DOC 좌석 몫이었으나 같은 패키지를
/// 만지는 이 좌석(P3)으로 재배정됐다.
///
/// 시드(`V2__seed_data.sql`) 기준 —
/// - academy 1(`바래다학원 A`)·2(`바래다학원 B`) 는 `active`, academy
///   3(`바래다학원 C`) 는 `inactive` — §2.1 의 "비활성 학원은 결과에서
///   제외" 를 실증할 재료.
/// - `staffPending`(account 4)·`parentPending`(account 8) 은 `pending`.
/// - `studentRejected`(account 11) 은 `rejected`,
///   `signup_request.reject_reason = '재학증명서 미제출'`.
///
/// **되돌릴 수 없는 상태를 만드는 시험 2개**(§2.2 신규 가입 · §2.4 재신청)는
/// 각자 끝에 `POST /dev/reset` 으로 시드를 되돌린다 — §2.4 자체는 재신청
/// 이후로 되돌아갈 방법을 정의하지 않는다(§2.4 전문 확인: 응답 필드가
/// `status`·`requested_at` 뿐이고 취소 엔드포인트가 없다). `dart_test.yaml`
/// 의 `concurrency: 1` 덕에 이 초기화가 도는 동안 다른 `real_backend_p*`
/// 파일이 같은 스키마를 동시에 읽지 않는다(그 파일들과 같은 근거).
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

  /// 시드를 되돌린다 — `parentA1` 은 이미 승인된 계정이라 이 초기화 자체가
  /// 되돌리려는 대상(가입·재신청으로 만든 상태 변화)과 무관하다.
  Future<void> resetSeed() async {
    final resetClient = buildClientFor('signup-reset');
    await resetClient.auth.login(loginId: 'parentA1', password: 'password');
    await resetClient.dio.post<Map<String, dynamic>>('/dev/reset');
  }

  test(
    '목표 — §2.1 학원 검색이 비활성 학원을 결과에서 제외하고, '
    'q 누락은 422 VALIDATION_FAILED (반복 실행 가능·상태 변경 없음)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final auth = buildClientFor('signup-search').auth;

      final results = await auth.searchAcademies('바래다');
      expect(
        results.map((a) => a.name),
        containsAll(['바래다학원 A', '바래다학원 B']),
      );
      expect(results.map((a) => a.name), isNot(contains('바래다학원 C')));

      // q 누락 — `searchAcademies` 는 항상 쿼리를 실어 보내므로 원문
      // Dio 호출로 직접 재현한다.
      final rawDio = buildClientFor('signup-search-raw').dio;
      await _expectApiError(
        () => rawDio.get<dynamic>('/academies/search'),
        statusCode: 422,
        errorCode: 'VALIDATION_FAILED',
      );
    },
  );

  test(
    '목표 — §2.2 회원가입이 pending 계정을 만들고, 아이디 중복은 '
    '409 DUPLICATE_LOGIN_ID (성공 분기는 /dev/reset 으로 되돌린다)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final auth = buildClientFor('signup-create').auth;
      final searchAuth = buildClientFor('signup-create-search').auth;
      final academies = await searchAuth.searchAcademies('바래다학원 A');
      final academyId = academies.first.id;

      final uniqueLoginId =
          'fer3pSignup${DateTime.now().millisecondsSinceEpoch}';
      final response = await auth.signup(
        SignupRequest(
          role: 'parent',
          loginId: uniqueLoginId,
          password: 'password',
          name: 'FE-R3 가입 시험',
          phone: '010-9999-0000',
          academyId: academyId,
        ),
      );
      expect(response.accountStatus, 'pending');
      expect(response.approver, 'staff');

      // 409 — 이미 존재하는 로그인 아이디(parentA1). 계정을 새로 만들지
      // 않으므로 이 분기 자체는 시드를 더럽히지 않는다.
      final dupAuth = buildClientFor('signup-dup').auth;
      await _expectApiError(
        () => dupAuth.signup(
          SignupRequest(
            role: 'parent',
            loginId: 'parentA1',
            password: 'password',
            name: '중복 시험',
            phone: '010-9999-0001',
            academyId: academyId,
          ),
        ),
        statusCode: 409,
        errorCode: 'DUPLICATE_LOGIN_ID',
      );

      // 방금 만든 계정·signup_request 는 되돌릴 API 가 없다 — 시드로 복구.
      await resetSeed();
    },
  );

  test(
    '목표 — §2.3 승인 대기 조회가 pending·rejected 두 상태를 정확히 '
    '돌려준다 (반복 실행 가능·상태 변경 없음)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final pendingClient = buildClientFor('signup-status-pending');
      await pendingClient.auth.login(
        loginId: 'parentPending',
        password: 'password',
      );
      final pendingStatus = await pendingClient.auth.signupStatus();
      expect(pendingStatus.status, AccountStatus.pending);
      expect(pendingStatus.rejectReason, isNull);
      expect(pendingStatus.academyName, '바래다학원 A');

      final rejectedClient = buildClientFor('signup-status-rejected');
      await rejectedClient.auth.login(
        loginId: 'studentRejected',
        password: 'password',
      );
      final rejectedStatus = await rejectedClient.auth.signupStatus();
      expect(rejectedStatus.status, AccountStatus.rejected);
      expect(rejectedStatus.rejectReason, '재학증명서 미제출');
    },
  );

  test(
    '목표 — §2.4 재신청이 rejected 를 pending 으로 되돌리고, 재차 '
    '호출은 409 REAPPLY_NOT_ALLOWED (끝에 /dev/reset 으로 되돌린다)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final client = buildClientFor('signup-reapply');
      await client.auth.login(
        loginId: 'studentRejected',
        password: 'password',
      );
      final searchAuth = buildClientFor('signup-reapply-search').auth;
      final academies = await searchAuth.searchAcademies('바래다학원 B');
      final academyId = academies.first.id;

      final response = await client.auth.reapply(academyId: academyId);
      expect(response.status, AccountStatus.pending);

      // rejected 가 아닌 상태에서 재신청 — 같은(이미 pending 이 된) 계정
      // 토큰으로 재호출하므로 추가 부수효과가 없다.
      await _expectApiError(
        () => client.auth.reapply(academyId: academyId),
        statusCode: 409,
        errorCode: 'REAPPLY_NOT_ALLOWED',
      );

      // studentRejected 를 다시 rejected 로 — §2.4 는 되돌아갈 방법을
      // 정의하지 않는다(§2.4 전문 재확인, 판단 근거 1항).
      await resetSeed();
    },
  );
}
