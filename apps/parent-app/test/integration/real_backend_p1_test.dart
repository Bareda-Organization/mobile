import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/change_requests/data/change_request_api.dart';
import 'package:parent_app/core/constants/api_constants.dart';
import 'package:parent_app/core/runs/data/run_api.dart';
import 'package:parent_app/core/students/data/student_api.dart';
import 'package:parent_app/features/child_link/data/link_api.dart';
import 'package:parent_app/features/home/data/notification_api.dart';
import 'package:parent_app/features/schedule/data/weekly_address_api.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// 실제 시크릿 스토리지 없이 값만 메모리에 담아 두는 가짜 구현
// (`real_backend_auth_test.dart` 와 같은 구조).
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

/// `--dart-define=API_BASE_URL` 로 지정한 서버를 실제로 때리는 계약
/// 시험 — P1 이 담당한 홈·일정·자녀연결 화면이 쓰는 §3 엔드포인트 전부를
/// 최소 1회씩 실제로 호출해 파싱까지 성공하는지 확인한다. 서버가 안 떠
/// 있으면 `setUpAll` 헬스체크가 전체를 환경 문제로 건너뛴다
/// (`real_backend_auth_test.dart` 와 같은 구조).
///
/// 시드(`V2__seed_data.sql`) 기준 — `parentA1`(account 5·guardian 1)은
/// 학생 1(김철수)·2(김영희)에 이미 연결돼 있고, `studentA4`(account 10·
/// student 4·이하늘)는 **아직 연결돼 있지 않다**. 이 어긋남이 바로
/// 자녀연결(§3.2~§3.4) 흐름의 시험 재료다 — 이미 연결된 계정끼리는
/// 이 흐름을 다시 시연할 수 없다.
void main() {
  // ⚠ 여기 박아 두면 안 된다 — 앱 내부(`di.dart`)는 `ApiConstants.baseUrl`
  // 을 통해 `--dart-define=API_BASE_URL` 값을 그대로 쓴다. 리터럴을 박아
  // 두면 `--dart-define` 으로 다른 포트를 줘도 이 파일이 그 값을 무시해
  // 항상 건너뛰거나 엉뚱한 서버를 때린다(`auto_login_test.dart` 와 같은
  // 근거, f766c27).
  const baseUrl = ApiConstants.baseUrl;
  late bool backendReachable;

  setUpAll(() async {
    // 이 시험 파일 전체가 플랫폼 인스턴스를 하나만 공유한다 — 저장 키
    // 앞에 붙는 `storagePrefix` 로 계정별 토큰을 가른다. 클라이언트를
    // 만들 때마다 이 줄을 다시 실행하면 먼저 만든 클라이언트(예: 학부모)의
    // `TokenStorage` 가 참조하던 플랫폼이 새 빈 맵으로 조용히 바뀌어,
    // 그 클라이언트는 이후 호출에서 저장했던 토큰을 읽지 못해 401 이
    // 난다 — 두 계정을 한 시험에서 같이 쓰는 자녀연결 왕복 시험에서
    // 실제로 이 형태로 걸렸다(`FlutterSecureStorage` 는 `const` 생성자라
    // 매 호출마다 `FlutterSecureStoragePlatform.instance` 를 새로 읽는다).
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
    '목표 — parentA1 이 §3.1·§3.5·§3.7·§3.9·§3.12·§3.13 을 실제로 호출한다',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final parent = buildClientFor('p1-parent');
      await parent.auth.login(loginId: 'parentA1', password: 'password');

      // §3.1 — 연결 자녀 목록. 시드상 학생 1(김철수)·2(김영희)가 있어야 한다.
      final students = await StudentApi(dio: parent.dio).getMyStudents();
      expect(students.map((s) => s.name), containsAll(['김철수', '김영희']));
      final chulsoo = students.firstWhere((s) => s.name == '김철수');

      // §3.5 — 당일 회차. run_rider 시드(run 2·3)가 학생 1 을 걸고 있다.
      final runs = await RunApi(
        dio: parent.dio,
      ).getRuns(chulsoo.studentId);
      expect(runs, isNotEmpty);

      // §3.7 — 요일×방향 주소. 시드가 학생 1 에 7일×2방향=14건을 심어 둔다.
      final addresses = await WeeklyAddressApi(
        dio: parent.dio,
      ).getWeeklyAddress(chulsoo.studentId);
      expect(addresses, hasLength(14));

      // §3.9 — 일일 변경 신청 이력(비어 있어도 파싱은 성공해야 한다).
      final changeRequests = await ChangeRequestApi(
        dio: parent.dio,
      ).getChangeRequests(chulsoo.studentId);
      expect(changeRequests.pendingCount, isA<int>());

      // §3.12 — 알림 목록. 시드 notification_log #1 이 이 계정(account 5)
      // 앞으로 미읽음 상태로 와 있어야 한다.
      final notificationApi = NotificationApi(dio: parent.dio);
      final page = await notificationApi.getNotifications();
      expect(page.items, isNotEmpty);

      // §3.13 — 읽음 처리. 이미 읽었어도(재실행) 서버가 멱등하게 204 를
      // 돌려주는지까지가 이 호출의 관심사라 별도 unread 필터 없이 첫
      // 항목으로 호출한다.
      await notificationApi.markRead(page.items.first.notificationId);
    },
  );

  test(
    '목표 — 학부모↔학생 자녀연결(§3.2~§3.4)을 parentA1·studentA4 로 '
    '실제로 왕복한다 (이미 연결돼 있으면 건너뛴다)',
    () async {
      if (!backendReachable) {
        markTestSkipped('환경 문제: $baseUrl 백엔드 미기동');
        return;
      }
      final parent = buildClientFor('p1-link-parent');
      await parent.auth.login(loginId: 'parentA1', password: 'password');
      final linkApiParent = LinkApi(dio: parent.dio);

      final before = await StudentApi(dio: parent.dio).getMyStudents();
      if (before.any((s) => s.name == '이하늘')) {
        // 이전 실행에서 이미 연결을 끝냈다 — 재연결을 시도하면 서버가
        // 거부하므로(멱등 없음, §3.2 는 신규 요청 생성) 여기서 멈춘다.
        // 읽기 결과가 이미 존재한다는 것 자체가 §3.2~§3.4 가 실제로
        // 동작했다는 증거다.
        return;
      }

      // §3.2 — 학부모가 연결을 요청.
      final requestResult = await linkApiParent.requestLink('studentA4');
      expect(requestResult.linkRequestId, isNotEmpty);

      // §3.3 — 학생이 인증 코드를 발급.
      final student = buildClientFor('p1-link-student');
      await student.auth.login(loginId: 'studentA4', password: 'password');
      final codeResult = await LinkApi(dio: student.dio).generateLinkCode();
      expect(codeResult.code, isNotEmpty);

      // §3.4 — 학부모가 코드로 확인 완료.
      final confirmResult = await linkApiParent.confirmLink(codeResult.code);
      expect(confirmResult.name, '이하늘');

      final after = await StudentApi(dio: parent.dio).getMyStudents();
      expect(after.map((s) => s.name), contains('이하늘'));
    },
  );
}
