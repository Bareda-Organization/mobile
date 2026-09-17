import 'package:dio/dio.dart';

/// `real_backend_auth_test.dart` 목표 9(`driverBlocked` 는 로그인이 항상 실패해야 한다)가
/// 첫 실행만 초록이던 문제를 되돌린다.
///
/// **원인 — 이 패키지 밖에서 계정을 되돌릴 수 없이 풀어 버린다.** 백엔드에는 관리자용
/// 차단 해제 API(`AccountUnblockCommandService`)는 있지만 **재차단 API 는 없다**. 다른 앱
/// (매니저 앱)의 실서버 계약 시험이 같은 공유 시드 DB 에서 `driverBlocked` 를 대상으로
/// 그 해제 흐름을 돌리면, 이 패키지의 목표 9 는 그다음부터 영원히 "로그인 성공"을 받는다
/// — 코드 결함이 아니라 크로스 패키지 상태 오염이다.
///
/// **판단 근거 — `real_backend_target.dart`(parent-app)·매니저 앱의 F5 판정과 같은
/// "조건부 `POST /dev/reset`" 형태를 따르되, 코드는 공유하지 않고 새로 둔다.** 저쪽 둘은
/// *시각*(출발 시각까지 남은 여유)을 판정 기준으로 쓰고, 여기는 *계정 차단 여부*를 판정
/// 기준으로 쓴다 — 판정 로직 자체가 다르고, 공유하려면 그 파일들이 있는 `parent-app`·
/// `manager-app` 을 고쳐야 하는데 이 작업 범위는 `baraeda_core/test/**` 뿐이다. 형태(먼저
/// 값싸게 확인하고, 어긋났을 때만 비싼 재구성을 돈다)만 재사용한다 — 무조건 초기화하면
/// 이미 안전한 회차에도 Flyway clean+migrate 를 매번 돌려 실행 시간만 늘어난다.
Future<void> ensureDriverBlockedSeedIsIntact(String baseUrl) async {
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  try {
    if (await _driverBlockedIsStillBlocked(dio)) return;
    await _resetViaParentA1(dio);
  } finally {
    dio.close();
  }
}

/// `driverBlocked`/`password` 로 로그인을 시도한다. 계정이 여전히 차단 상태면
/// `Account.assertNotBlocked()` 가 비밀번호 대조보다 먼저 403 `AUTH_ACCOUNT_BLOCKED` 를
/// 던지므로(상태를 바꾸는 부수효과 없음), 그 코드를 확인하는 것이 "아직 안전하다"의 증거다.
/// 그 외 응답(로그인 성공 포함 · 다른 오류 코드 · 연결 실패)은 전부 "확인 못 함"으로 보고
/// 안전한 쪽(재구성)으로 넘긴다 — 이 호출은 `backendReachable` 이 참인 뒤에만 불리므로
/// 연결 실패 쪽 재구성 시도는 그 자체가 새로운 신호다.
Future<bool> _driverBlockedIsStillBlocked(Dio dio) async {
  try {
    await dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'login_id': 'driverBlocked', 'password': 'password'},
    );
    return false;
  } on DioException catch (e) {
    final body = e.response?.data;
    if (body is! Map<String, dynamic>) return false;
    final error = body['error'];
    return error is Map<String, dynamic> &&
        error['code'] == 'AUTH_ACCOUNT_BLOCKED';
  }
}

/// `/dev/reset` 은 인증을 요구한다(`@AuthenticatedOnly`, 누구든 가능). `driverBlocked` 는
/// 방금 확인에서 로그인에 성공했을 수도·실패했을 수도 있어 그 결과로 만든 토큰에 기대지
/// 않고, 이미 다른 시험들이 안전하다고 검증해 둔 읽기 전용 계정 `parentA1` 로 새로 로그인해
/// 토큰을 받는다(`real_backend_target.dart` 와 같은 계정).
Future<void> _resetViaParentA1(Dio dio) async {
  final loginResponse = await dio.post<Map<String, dynamic>>(
    '/auth/login',
    data: {'login_id': 'parentA1', 'password': 'password'},
  );
  final loginData = loginResponse.data!['data'] as Map<String, dynamic>;
  dio.options.headers['Authorization'] = 'Bearer ${loginData['access_token']}';
  await dio.post<Map<String, dynamic>>('/dev/reset');
}
