import 'package:baraeda_core/auth/account_status.dart';
import 'package:baraeda_core/auth/auth_api.dart';
import 'package:baraeda_core/error/failure.dart';
import 'package:baraeda_core/network/api_client.dart';
import 'package:baraeda_core/network/dio_error_mapper.dart';
import 'package:baraeda_core/storage/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// 실제 시크릿 스토리지 없이 값만 메모리에 담아 두는 가짜 구현
// (`api_client_auth_test.dart`·`token_storage_test.dart` 와 같은 구조).
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
}

/// `localhost:8080` 을 실제로 때리는 계약 시험 — F2 목표 표 7·8·9·11 항.
/// `flutter test` 가 도는 동안 로컬 백엔드(`docker compose up -d postgres
/// redis` + `./gradlew bootRun`)가 떠 있어야 하고, 없으면 이 그룹 전체가
/// 연결 실패로 죽는다. 그 실패는 코드 결함이 아니라 환경 문제이므로
/// `setUpAll` 에서 헬스체크로 미리 갈라 별도 실패 메시지를 남긴다.
///
/// ⚠ 아래 계정은 Flutter 갈래에 배정된 시드 계정만 쓴다
/// (`db/migration-local/V2__seed_data.sql`) — `parentA1` 은 실패 로그인
/// 누적 시험에 쓰지 않고, `driverBlocked` 는 상태를 바꾸는 어떤 호출도
/// 하지 않는다(읽기 전용 공유 계정).
void main() {
  const baseUrl = 'http://localhost:8080/api/v1';
  late bool backendReachable;

  setUpAll(() async {
    final probe = Dio(BaseOptions(baseUrl: baseUrl));
    try {
      await probe.get<dynamic>(
        '/academies/search',
        queryParameters: {'q': '바래다'},
      );
      backendReachable = true;
    } on DioException catch (e) {
      // 422·404 등 HTTP 응답이 오면 서버는 떠 있는 것이다 — 연결 자체가
      // 안 되는 경우(connectionError 계열)만 "서버 부재"로 분류한다.
      backendReachable = e.response != null;
    } finally {
      probe.close();
    }
  });

  // `AuthApi` 는 `_dio`·`_tokenStorage` 를 비공개로 감춘다(§ 아키텍처 결정 —
  // presentation 은 domain 인터페이스만 거치고, 시험은 이 계약이 필요할 때만
  // 원 재료에 접근한다). 여기서는 §2 목록 밖 엔드포인트(`/notifications`)를
  // 직접 부르거나 저장된 토큰 유무를 확인해야 해서 `client.dio`·`storage` 를
  // 함께 들고 있는다.
  ({AuthApi auth, Dio dio, TokenStorage storage}) buildAuthApi() {
    FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
    final storage = TokenStorage(
      accessTokenKey: 'it-access',
      refreshTokenKey: 'it-refresh',
    );
    final client = ApiClient(tokenStorage: storage, baseUrl: baseUrl);
    final auth = AuthApi(dio: client.dio, tokenStorage: storage);
    return (auth: auth, dio: client.dio, storage: storage);
  }

  test(
    '목표 7 — pending 계정은 허용 목록 밖 호출에서 403 AUTH_PENDING 을 받는다 '
    '(실제 호출 1회)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: localhost:8080 백엔드 미기동');
        return;
      }
      final (:auth, :dio, storage: _) = buildAuthApi();
      final login = await auth.login(
        loginId: 'parentPending',
        password: 'password',
      );
      expect(login.status, AccountStatus.pending);

      // §2.3·§2.7·§2.10·§2.11 은 pending 허용 목록 — 그 밖의
      // `GET /notifications`(§3.12) 로 게이트를 확인한다.
      Failure? failure;
      try {
        await dio.get<dynamic>('/notifications');
      } on DioException catch (e) {
        failure = mapDioExceptionToFailure(e);
      }

      expect(failure, isA<ApiFailure>());
      final apiFailure = failure! as ApiFailure;
      expect(apiFailure.code, 'AUTH_PENDING');
      expect(apiFailure.statusCode, 403);

      // 허용 목록 안(§2.10)은 여전히 통과해야 한다 — 게이트가 전체 차단이
      // 아니라 허용 목록만 열어 둔 것인지 함께 확인.
      final me = await auth.me();
      expect(me.status, AccountStatus.pending);
    },
  );

  test(
    '목표 8 — rejected 계정은 signup-status 응답에 거절 사유를 담아 온다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: localhost:8080 백엔드 미기동');
        return;
      }
      final (:auth, dio: _, storage: _) = buildAuthApi();
      final login = await auth.login(
        loginId: 'studentRejected',
        password: 'password',
      );
      expect(login.status, AccountStatus.rejected);

      final status = await auth.signupStatus();
      expect(status.status, AccountStatus.rejected);
      // 시드 데이터(V2__seed_data.sql:76)에 고정된 문구.
      expect(status.rejectReason, '재학증명서 미제출');

      // §2.4 재신청(=재신청 진입점) 자체가 허용 목록 안에 있다는 것도
      // 같은 호출로 확인 — 존재하지 않는 학원 id 를 줘 응답 형태만 본다.
      // 재신청 성공 경로는 계정 상태를 pending 으로 되돌려 시드를 오염시키므로
      // 여기서는 실행하지 않고, "허용은 되지만 검증에서 걸린다"만 확인한다.
      Failure? failure;
      try {
        await auth.reapply(academyId: 'not-a-real-academy-id');
      } on DioException catch (e) {
        failure = mapDioExceptionToFailure(e);
      }
      expect(failure, isA<ApiFailure>());
      // AUTH_REJECTED 가 아니라(=허용 목록 안이라는 뜻) 다른 사유로 거부됨.
      expect((failure! as ApiFailure).code, isNot('AUTH_REJECTED'));
    },
  );

  test(
    '목표 9 — blocked 계정은 로그인 자체가 실패하고 사유가 담겨 온다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: localhost:8080 백엔드 미기동');
        return;
      }
      final (:auth, dio: _, :storage) = buildAuthApi();

      Failure? failure;
      try {
        // driverBlocked 는 공유 읽기전용 계정 — 비밀번호는 시드값 그대로
        // 넣는다(틀린 비밀번호를 시도하지 않는다: 이미 blocked 인 계정에도
        // 실패 카운터가 더 쌓이는지는 이 시험의 관심사가 아니고, 굳이
        // 상태를 더 건드릴 이유가 없다).
        await auth.login(loginId: 'driverBlocked', password: 'password');
      } on DioException catch (e) {
        failure = mapDioExceptionToFailure(e);
      }

      expect(failure, isA<ApiFailure>());
      final apiFailure = failure! as ApiFailure;
      expect(apiFailure.code, 'AUTH_ACCOUNT_BLOCKED');
      expect(apiFailure.statusCode, 403);
      // 로그인 실패라 토큰이 저장되지 않았어야 한다.
      expect(await storage.readAccessToken(), isNull);
    },
  );

  test(
    '목표 11 — 학원 검색은 비활성 학원(운영정지)을 제외한다 (실제 호출)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: localhost:8080 백엔드 미기동');
        return;
      }
      final (:auth, dio: _, storage: _) = buildAuthApi();

      // 시드 academy 3건: A(active)·B(active)·C(inactive, code BARAEDA-C).
      final all = await auth.searchAcademies('바래다학원');
      expect(all.map((a) => a.code), containsAll(['BARAEDA-A', 'BARAEDA-B']));
      expect(all.map((a) => a.code), isNot(contains('BARAEDA-C')));

      // C 를 정확히 겨냥한 검색어를 줘도 결과가 비어야 한다 — 이름이
      // 일부만 일치해서 안 나온 게 아니라 상태로 걸러졌다는 것을 분리해
      // 확인한다.
      final onlyC = await auth.searchAcademies('바래다학원 C');
      expect(onlyC, isEmpty);
    },
  );
}
