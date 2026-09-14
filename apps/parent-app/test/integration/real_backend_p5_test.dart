@Tags(['real_backend'])
library;

import 'dart:io';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/students/data/student_api.dart';
import 'package:parent_app/features/live_map/data/bus_position_api.dart';
import 'package:parent_app/features/route/data/route_api.dart';
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
/// 검사한다 (`real_backend_p4_test.dart` 와 같은 헬퍼).
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
/// 시험 — 목표 8: §3.10(상세 노선)·§3.11(실시간 위치)를 실백엔드로
/// 호출하고, 성공 경로와 두 예외 경로(`404 STUDENT_NOT_FOUND` ·
/// `403 FORBIDDEN`)를 재현한다. 서버가 안 떠 있으면 `setUpAll` 헬스체크가
/// 전체를 환경 문제로 건너뛴다(`real_backend_p1_test.dart` 와 같은 구조).
///
/// **404 STUDENT_NOT_FOUND 를 만드는 방법 — 판단 근거.** 시드
/// (`V2__seed_data.sql`)에는 "연결은 살아 있는데 학생만 사라진" 상태가
/// 없고, 학생 퇴원 API(`DELETE /staff/students/{id}`)는
/// `StudentCommandService.withdraw()` 가 학생 소프트 삭제와 보호자 연결
/// 해제를 **같은 트랜잭션에서 함께** 처리한다 — 그래서 퇴원 API 를 쓰면
/// 연결도 함께 끊겨 `assertLinkedChild()` 가 먼저 `403` 을 던지고
/// `404` 경로(`findByIdAndAcademyIdAndDeletedAtIsNull`)에 닿지 못한다.
/// 이 상태(연결은 살아 있는데 학생 행만 `deleted_at` 이 선 상태)는
/// `LinkedChildLookup` 자바독이 "죽은 가지가 아니다" 라고 직접 문서화한
/// 시나리오이지만, **정상 API 경로로는 재현할 수 없다** — 그래서
/// `setUpAll` 에서 이 좌석 전용 DB(`schoolbus_fer3_p`, 포트 8152)에
/// 직접 SQL 로 그 상태를 만든다(`UPDATE student SET deleted_at = now()
/// WHERE id = 5 AND deleted_at IS NULL`). 대상은 student 5(최지우) ·
/// guardian 3(parentA3 계정)로, 이 저장소의 다른 실백엔드 시험 파일이
/// 그 학생의 노선·위치 데이터를 건드리지 않는 것을 `grep` 으로 확인했다
/// (`parentA3` 는 `real_backend_p2_test.dart` 에서만 쓰이고 계정 설정
/// 시험 용도다). 이 SQL 은 `deleted_at IS NULL` 조건이 있어 **멱등**하다
/// — 반복 실행해도 두 번째부터는 0행이 갱신되고 상태가 더 나빠지지
/// 않는다(`phase-goal-loop.md §5.4` 의 "연속 4회 실행" 요구를 만족한다).
///
/// ⚠ **이식성 한계** — `docker exec school-bus-postgres-1 psql ...` 로
/// 고정 컨테이너 이름을 호출한다. 이 좌석의 전용 자원(포트 8152 ·
/// DB `schoolbus_fer3_p`)이 공유 postgres 컨테이너
/// `school-bus-postgres-1` 위에 있다는 전제가 깨지면(다른 환경 · CI)
/// 이 도구가 없거나 실패하며, 그 경우 404 시험 2건만 환경 문제로
/// 건너뛴다 — 403·성공 경로 시험은 이 전제에 의존하지 않는다.
void main() {
  final baseUrl = requireRealBackendBaseUrl();
  late bool backendReachable;
  late bool student5FixtureReady;

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

    if (backendReachable) {
      await ensureParentSeedIsSafeForTiming(baseUrl);
    }

    student5FixtureReady = false;
    if (backendReachable) {
      try {
        const softDeleteStudent5Sql =
            'UPDATE student SET deleted_at = now() '
            'WHERE id = 5 AND deleted_at IS NULL;';
        final result = await Process.run('docker', [
          'exec',
          'school-bus-postgres-1',
          'psql',
          '-U',
          'schoolbus',
          '-d',
          'schoolbus_fer3_p',
          '-c',
          softDeleteStudent5Sql,
        ]);
        student5FixtureReady = result.exitCode == 0;
      } on ProcessException {
        student5FixtureReady = false;
      }
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
    '목표 — §3.10 연결된 자녀(학생1/parentA1)의 상세 노선을 반환하고, '
    'ETA·승하차지별 탑승 인원·기사 연락처가 부재하다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final parent = buildClientFor('p5-a-parent');
      await parent.auth.login(loginId: 'parentA1', password: 'password');
      final students = await StudentApi(dio: parent.dio).getMyStudents();
      final chulsoo = students.firstWhere((s) => s.name == '김철수');

      // 원본 JSON(봉투는 인터셉터가 이미 벗긴 상태)에서 직접 부재를
      // 확인한다 — 모델에 필드가 없는 것만으로는 "서버가 안 보낸다" 를
      // 보장하지 못한다(모델이 무시했을 수도 있다).
      final raw = await parent.dio.get<Map<String, dynamic>>(
        '/students/${chulsoo.studentId}/route',
      );
      final body = raw.data!;
      expect(body.containsKey('eta'), isFalse);
      expect(body['driver'], isA<Map<String, dynamic>>());
      expect(
        (body['driver'] as Map<String, dynamic>).containsKey('phone'),
        isFalse,
      );
      final stops = (body['stops'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(stops, isNotEmpty);
      for (final stop in stops) {
        expect(stop.containsKey('eta'), isFalse);
        expect(stop.containsKey('passenger_count'), isFalse);
        expect(stop.containsKey('rider_count'), isFalse);
      }

      final route = await RouteApi(
        dio: parent.dio,
      ).getRoute(chulsoo.studentId);
      expect(route.runId, isNotEmpty);
      expect(route.busNo, isNotEmpty);
      expect(route.driver.name, isNotEmpty);
      expect(route.escort.name, isNotEmpty);
      expect(route.escort.phone, isNotEmpty);
      expect(route.myStopId, isNotEmpty);
      expect(route.stops, isNotEmpty);
    },
  );

  test(
    '목표 — §3.11 연결된 자녀(학생1/parentA1)의 실시간 위치를 반환한다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final parent = buildClientFor('p5-b-parent');
      await parent.auth.login(loginId: 'parentA1', password: 'password');
      final students = await StudentApi(dio: parent.dio).getMyStudents();
      final chulsoo = students.firstWhere((s) => s.name == '김철수');

      final raw = await parent.dio.get<Map<String, dynamic>>(
        '/students/${chulsoo.studentId}/bus-position',
      );
      expect(raw.data!.containsKey('eta'), isFalse);

      final position = await BusPositionApi(
        dio: parent.dio,
      ).getBusPosition(chulsoo.studentId);
      expect(position.runId, isNotEmpty);
      expect(position.busNo, isNotEmpty);
    },
  );

  test(
    '목표 — §3.10·§3.11 연결 부재 자녀(학생3, parentA1 은 미연결)는 '
    '403 FORBIDDEN 을 반환한다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final parent = buildClientFor('p5-c-parent');
      await parent.auth.login(loginId: 'parentA1', password: 'password');
      final routeApi = RouteApi(dio: parent.dio);
      final busPositionApi = BusPositionApi(dio: parent.dio);

      await _expectApiError(
        () => routeApi.getRoute('3'),
        statusCode: 403,
        errorCode: 'FORBIDDEN',
      );
      await _expectApiError(
        () => busPositionApi.getBusPosition('3'),
        statusCode: 403,
        errorCode: 'FORBIDDEN',
      );
    },
  );

  test(
    '목표 — §3.10·§3.11 존재하지 않는 학생 ID 도 403 FORBIDDEN 을 '
    '반환한다(연결 부재와 동일 취급 — 존재 자체를 숨긴다)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final parent = buildClientFor('p5-d-parent');
      await parent.auth.login(loginId: 'parentA1', password: 'password');
      final routeApi = RouteApi(dio: parent.dio);
      final busPositionApi = BusPositionApi(dio: parent.dio);

      await _expectApiError(
        () => routeApi.getRoute('999999'),
        statusCode: 403,
        errorCode: 'FORBIDDEN',
      );
      await _expectApiError(
        () => busPositionApi.getBusPosition('999999'),
        statusCode: 403,
        errorCode: 'FORBIDDEN',
      );
    },
  );

  test(
    '목표 — §3.10·§3.11 연결은 살아 있는데 학생이 소프트 삭제된 상태 '
    '(학생5/parentA3)는 404 STUDENT_NOT_FOUND 를 반환한다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      if (!student5FixtureReady) {
        markTestSkipped(
          '환경 문제: student5 소프트 삭제 픽스처를 만들지 못했다 '
          '(docker exec school-bus-postgres-1 실패 — 이 좌석 전용 '
          '컨테이너 전제가 깨졌을 가능성)',
        );
        return;
      }
      final parent = buildClientFor('p5-e-parent');
      await parent.auth.login(loginId: 'parentA3', password: 'password');
      final routeApi = RouteApi(dio: parent.dio);
      final busPositionApi = BusPositionApi(dio: parent.dio);

      await _expectApiError(
        () => routeApi.getRoute('5'),
        statusCode: 404,
        errorCode: 'STUDENT_NOT_FOUND',
      );
      await _expectApiError(
        () => busPositionApi.getBusPosition('5'),
        statusCode: 404,
        errorCode: 'STUDENT_NOT_FOUND',
      );
    },
  );
}
