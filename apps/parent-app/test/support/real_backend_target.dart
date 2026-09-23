import 'package:dio/dio.dart';
import 'package:parent_app/core/constants/api_constants.dart';

/// 실서버 계약 시험이 붙을 주소. **주소를 받지 못하면 던진다.**
///
/// ⚠ 기본값으로 조용히 `localhost:8080` 에 붙는 경로를 없애는 것이 이 함수의 전부다.
/// 그 기본값은 조율자의 시드 서버라, `--dart-define=API_BASE_URL` 을 빠뜨린 실행이
/// 시드 DB 에 실제 레코드를 만든다(2026-09-13 에 3회 발생 · 비상 신고 8건 생성).
/// 발주문의 경고 문구로는 세 번 다 막지 못했다 — 좌석이 "실서버 시험을 제외했다" 고
/// 믿는 상태에서는 인자를 붙일 이유가 없기 때문이다. 그래서 문구가 아니라 구조로 막는다.
///
/// 백엔드 없이 나머지 시험만 돌리려면 `flutter test --exclude-tags real_backend`.
String requireRealBackendBaseUrl() {
  if (!const bool.hasEnvironment('API_BASE_URL')) {
    throw StateError(
      '실서버 계약 시험에는 대상 주소가 필요하다. '
      'flutter test --dart-define=API_BASE_URL=http://localhost:<전용포트>/api/v1 로 실행하라. '
      '주소를 생략하면 기본값 8080(조율자 시드 서버)으로 실제 요청이 나간다. '
      '백엔드 없이 돌리려면 --exclude-tags real_backend 를 쓴다.',
    );
  }
  return ApiConstants.baseUrl;
}

/// `--dart-define=FIXTURE_DB` — `docker exec` 로 SQL 픽스처를 심을 DB 이름.
///
/// **판단 근거 — 좌석 DB 이름을 소스에 박지 않고 `API_BASE_URL` 과 짝을 이루는
/// 별도 define 으로 받는다.** `API_BASE_URL` 의 포트 뒤에서 실제로 어느 DB 가
/// 물려 있는지는 그 서버를 띄운 사람만 안다(`./gradlew bootRun --args=
/// '--spring.datasource.url=...'` 의 `<네 DB>` 부분 — 회차마다 바뀐다). 이전
/// 코드처럼 `schoolbus_fer3_p` 를 문자열로 박으면 그 DB 가 사라지는 순간
/// 이 시험이 **영구히** 실패한다 — 그렇다고 포트→DB 매핑을 코드로 계산할
/// 수단도 없다(그 매핑은 기동 시점에만 정해지고 서버가 공개하지 않는다).
/// ⇒ 호출자가 `API_BASE_URL` 을 줄 때 같이 넘기게 만드는 것이 유일하게
/// 이 파일 밖 사실(어느 DB인지)에 코드가 의존하지 않는 방법이다.
///
/// **`requireRealBackendBaseUrl()` 과 달리 생략해도 던지지 않는다** — 이
/// 파일의 다른 시험(성공 경로·403)은 이 DB 픽스처가 전혀 필요 없다. 여기서
/// 던지면 `main()` 최상단에서 파일 전체가 죽어 무관한 시험까지 함께
/// 실패한다. 대신 호출부(`real_backend_p5_test.dart` 의 `setUpAll`)가
/// `null` 을 보고 그 픽스처가 필요한 시험 1건만 `markTestSkipped` 한다.
String? fixtureDbNameOrNull() => const bool.hasEnvironment('FIXTURE_DB')
    ? const String.fromEnvironment('FIXTURE_DB')
    : null;

/// F5 P2 목표 — `real_backend_p4_test.dart` 의 §3.6·§3.8 ②구간
/// `CHANGE_LIMIT_REACHED` 시험(Test C·Test F)은 run2 의 `depart_time`
/// (시드 적용 시각 + 20분)에 기대는데, 재시드 없이 그 시각이 지나면
/// `ChangeWindowPolicy.segmentOf` 가 run2 를 결정적으로 ②(APPROVAL_
/// REQUIRED)에서 ③(CLOSED)으로 넘긴다 — 그 순간부터 두 시험은 기대하는
/// `CHANGE_LIMIT_REACHED` 대신 `CHANGE_WINDOW_CLOSED` 를 받아 실패한다
/// (F5 P 판정문 실측 — 조율자가 depart_time 까지 8분 남은 시점을 확인했고
/// 그 뒤 실제로 실패 2건이 났다).
///
/// 매니저 앱(`F5 M3`)이 같은 형태(되돌릴 수 없는 상태가 시간이 지나면
/// 마른다)를 닫은 것과 같은 수단을 쓴다 — **조건부 `POST /dev/reset`**.
/// `parentA1` 으로 조회한다 — 이 계정은 학생 1(김철수)의 보호자라 run2·
/// run3·run6 전부 조회 가능하고, `real_backend_p4_test.dart` 의 기존
/// 시험들이 이미 같은 계정으로 run2·run3 를 호출하고 있어 **`M3` 이 밟은
/// "조회 계정이 그 자원에 배치돼 있지 않다" 함정은 이 앱에는 없다**
/// (run3 를 조회하려 별도 계정을 쓸 필요가 없다).
///
/// 안전 조건은 **run2 가 아직 존재하고, `moving`/`finished` 로 전이되지
/// 않았고, `depart_time` 까지 안전 여유(3분) 이상 남아 있는가**다. 매
/// 실행마다 무조건 초기화하지 않는 이유는 매니저 앱과 같다 — 이미 안전한
/// 상태에서까지 Flyway clean+migrate 를 다시 돌려 실행 시간을 늘리지
/// 않기 위해서다. 안전 여유를 두는 이유는 판정 조건 확인 시점과 시험
/// 파일이 실제로 §3.6·§3.8 을 호출하는 시점 사이에 다른 시험(§3.1~§3.5)
/// 실행 시간이 끼기 때문이다 — 여유가 0 이면 그 사이에 창이 닫힐 수 있다.
///
/// ⚠ `dart_test.yaml` 의 `concurrency: 1` 과 반드시 함께 쓴다 — 이
/// 초기화(Flyway clean+migrate, 순간적이지 않다)가 도는 동안 다른
/// real_backend 파일(`real_backend_p1~p3_test.dart`)이 같은 스키마를
/// 동시에 읽으면 전이 상태(테이블 없음·부분 시드)를 코드 결함과 구별할
/// 수 없이 관측한다 — `M3` 이 매니저 앱에서 밟은 것과 같은 함정이다.
Future<void> ensureParentSeedIsSafeForTiming(String baseUrl) async {
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  try {
    final loginResponse = await dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'login_id': 'parentA1', 'password': 'password'},
    );
    final loginData = loginResponse.data!['data'] as Map<String, dynamic>;
    dio.options.headers['Authorization'] =
        'Bearer ${loginData['access_token']}';

    if (!await _needsParentSeedReset(dio)) return;

    await dio.post<Map<String, dynamic>>('/dev/reset');
  } on DioException catch (e) {
    // 연결 거부(백엔드 미기동)만 삼킨다 — 각 시험 자신의 backendReachable
    // 판정에 맡기고, 여기서 던지면 "환경 문제"와 "코드 결함"을 가르는 각
    // 시험의 자체 판정(markTestSkipped)이 가려진다. **그 외(401 등)는
    // 던진다** — 로그인 실패는 시드 계정이 손상됐다는 신호라, 여기서
    // 삼키면 그 손상 상태를 안은 채 나머지 시험이 조용히 돈다(이월 6번,
    // F5 보고서에서 발견).
    if (e.type != DioExceptionType.connectionError) rethrow;
  } finally {
    dio.close();
  }
}

/// 안전 여유 — run2 의 `depart_time` 까지 이 시간 미만으로 남았으면
/// 리셋한다. 시험 파일 전체(§3.1~§3.9, 왕복 여러 건) 실행 시간을 덮을
/// 만큼 넉넉하게 잡는다.
const _safetyMargin = Duration(minutes: 3);

Future<bool> _needsParentSeedReset(Dio dio) async {
  final studentsResponse = await dio.get<Map<String, dynamic>>(
    '/me/students',
  );
  final studentsData = studentsResponse.data!['data'] as Map<String, dynamic>;
  final students = (studentsData['items'] as List).cast<Map<String, dynamic>>();
  final chulsoo = students.firstWhere((s) => s['name'] == '김철수');
  final studentId = chulsoo['student_id'];

  final runsResponse = await dio.get<Map<String, dynamic>>(
    '/students/$studentId/runs',
  );
  final runsData = runsResponse.data!['data'] as Map<String, dynamic>;
  final runs = (runsData['items'] as List).cast<Map<String, dynamic>>();

  Map<String, dynamic>? run2;
  for (final run in runs) {
    if (run['run_id'].toString() == '2') {
      run2 = run;
      break;
    }
  }
  // run2 자체가 없거나(연결 해제 등) 이미 moving/finished 로 전이됐으면
  // 그 자체로 ③구간이라 안전하지 않다.
  if (run2 == null) return true;
  final status = run2['run_status'] as String;
  if (status == 'moving' || status == 'finished') return true;

  final departTime = DateTime.parse(run2['depart_time'] as String);
  final now = DateTime.now().toUtc();
  return !departTime.isAfter(now.add(_safetyMargin));
}
