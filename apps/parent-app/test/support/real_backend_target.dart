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
