import 'package:dio/dio.dart';
import 'package:manager_app/core/constants/api_constants.dart';

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

/// F5 M3 목표 — `run2`(§4.4 출발 창 검사·§4.2 confirmed 존재 확인)와
/// `run3`(§4.5 도착 처리)는 실제 시계·영구 소모 상태에 의존한다. 같은 DB 로
/// 반복 실행하면 ①도착 처리가 불가역이라(취소 API 부재) 정류장이 바닥나
/// §4.5 가 건너뛰거나 ②시드의 상대 시각이 실제 시계 경과로 `run2` 의 출발
/// 창(depart_time ±10분) 위에 올라타 §4.4 가 기대하는 `START_WINDOW_CLOSED`
/// 대신 200(운행 시작 성공)을 받고, 그 성공이 `run2` 를 `confirmed` 에서
/// `moving` 으로 영구히 옮겨 §4.2(confirmed 회차 존재 확인)까지 함께
/// 무너뜨린다(F5 M3 보고서 1항 실측 — 두 실패가 같은 원인의 다른 증상).
///
/// 이 함수는 그 두 조건을 실제로 조회해, 안전하지 않을 때만
/// `POST /dev/reset`(로컬 전용, 인증만 요구)을 호출해 시드를 되돌린다 —
/// 매 실행마다 무조건 초기화하지 않는 이유는 이미 안전한 상태에서까지
/// Flyway clean+migrate 를 다시 돌려 실행 시간을 늘리지 않기 위해서다
/// (브리프 후보 (a) 채택, 후보 (c) "파일 병합"은 버렸다 — 이미 계약을
/// 검증하는 두 파일을 하나로 합치면 각 파일의 §4.1~§4.16 대응 관계가
/// 흐려진다).
///
/// ⚠ `dart_test.yaml` 의 `concurrency: 1` 과 반드시 함께 쓴다 — 이 초기화가
/// 도는 동안(Flyway clean+migrate, 순간적이지 않다) 다른 real_backend
/// 파일이 같은 스키마를 동시에 읽으면 전이 상태(테이블 없음·부분 시드)를
/// 관측한다. 이 함수는 `real_backend_manager_endpoints_test.dart` ·
/// `real_backend_run_flow_test.dart` 양쪽의 setUpAll 에서 호출된다 — 어느
/// 파일이 먼저 도는지는 파일 탐색 순서에 달려 있어 고정할 수 없으므로
/// 두 곳 다 이 확인을 반복한다. 먼저 실행된 쪽이 이미 리셋했다면 나중에
/// 도는 쪽의 호출은 조건이 이미 안전해 아무 것도 하지 않는다(멱등).
///
/// ⚠ 2026-09-14 실측 결함 수정 — run3 의 정류장 소모 여부를 확인하려면
/// `GET /runs/3/roster` 를 호출해야 하는데, run3 에 배치된 기사는
/// `driverA2` 이고 `driverA1` 은 배치돼 있지 않다. 첫 구현이 driverA1
/// 토큰으로 그 호출을 했다가 403 을 받았고, 그 예외가 아래 `on DioException`
/// 에 먹혀 "리셋이 필요 없다"로 조용히 오판됐다 — §4.5 가 3번 연속 정류장을
/// 소모한 뒤 4번째 실행에서 재시도까지 실패해 건너뛰는 형태로 드러났다
/// (판정 실행 1회차 4번째 반복에서 재현, 보고서 1항). run2 상태·창 확인은
/// driverA1 으로 충분해(`/manager/runs` 는 배치 여부와 무관하게 응답한다)
/// 그대로 두고, run3 조회에만 driverA2 로 별도 로그인한다.
Future<void> ensureManagerSeedIsSafeForTiming(String baseUrl) async {
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  try {
    final loginResponse = await dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'login_id': 'driverA1', 'password': 'password'},
    );
    final loginData = loginResponse.data!['data'] as Map<String, dynamic>;
    final token = loginData['access_token'] as String;
    dio.options.headers['Authorization'] = 'Bearer $token';

    if (!await _needsManagerSeedReset(dio, baseUrl)) return;

    await dio.post<Map<String, dynamic>>('/dev/reset');
  } on DioException {
    // 백엔드 미기동 등 — 각 시험 자신의 backendReachable 판정에 맡기고
    // 여기서는 삼킨다. 여기서 던지면 "환경 문제"와 "코드 결함"을 가르는
    // 각 시험의 자체 판정(예: §4.5 의 markTestSkipped)이 가려진다.
  } finally {
    dio.close();
  }
}

Future<bool> _needsManagerSeedReset(Dio dio, String baseUrl) async {
  final runsResponse = await dio.get<Map<String, dynamic>>('/manager/runs');
  final runsData = runsResponse.data!['data'] as Map<String, dynamic>;
  final runs = (runsData['items'] as List).cast<Map<String, dynamic>>();

  Map<String, dynamic>? run2;
  for (final run in runs) {
    if (run['run_id'] == '2') {
      run2 = run;
      break;
    }
  }
  // §4.2 가 요구하는 confirmed 회차가 이미 소모됨(예: 이전 실행이 §4.4 를
  // 실수로 통과시켜 run2 를 moving 으로 옮겼다).
  if (run2 == null || run2['run_status'] != 'confirmed') return true;

  final window = run2['start_window'] as Map<String, dynamic>;
  final from = DateTime.parse(window['from'] as String);
  final to = DateTime.parse(window['to'] as String);
  final now = DateTime.now().toUtc();
  // §4.4 가 요구하는 START_WINDOW_CLOSED 는 지금이 창 밖일 때만 성립한다.
  if (!now.isBefore(from) && !now.isAfter(to)) return true;

  // run3 에는 driverA1 이 배치돼 있지 않아 driverA1 토큰으로는 403 을
  // 받는다 — 별도로 driverA2 로 로그인해서 조회한다.
  final run3Dio = Dio(BaseOptions(baseUrl: baseUrl));
  try {
    final loginResponse = await run3Dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'login_id': 'driverA2', 'password': 'password'},
    );
    final loginData = loginResponse.data!['data'] as Map<String, dynamic>;
    run3Dio.options.headers['Authorization'] =
        'Bearer ${loginData['access_token']}';

    final rosterResponse = await run3Dio.get<Map<String, dynamic>>(
      '/runs/3/roster',
    );
    final rosterData = rosterResponse.data!['data'] as Map<String, dynamic>;
    final stops = (rosterData['stops'] as List).cast<Map<String, dynamic>>();
    var maxSeq = stops.first['seq'] as int;
    for (final stop in stops) {
      final seq = stop['seq'] as int;
      if (seq > maxSeq) maxSeq = seq;
    }
    final hasCandidate = stops.any(
      (stop) => stop['arrived_at'] == null && (stop['seq'] as int) != maxSeq,
    );
    // §4.5 가 요구하는 미도착 정류장(마지막 정류장 제외)이 바닥남.
    return !hasCandidate;
  } finally {
    run3Dio.close();
  }
}
