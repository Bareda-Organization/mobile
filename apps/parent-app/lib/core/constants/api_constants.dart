// API_SPEC §1.1 공통 규약 — 베이스 경로 · 클라이언트 종류.
// 값을 여러 파일에 흩지 않고 여기 한 곳에 모은다.

/// API 관련 상수. 호스트는 빌드 시 `--dart-define=API_BASE_URL=...` 로 덮어씀
/// (로컬 기본값은 School-Bus 백엔드의 `bootRun` 기본 포트).
abstract final class ApiConstants {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/api/v1',
  );

  /// API_SPEC §1.3 — 앱은 `X-Client-Type: app` 을 명시한다
  /// (미전달 시 기본값도 `app` 이지만, 명시해 서버 판정에 의존하지 않는다).
  static const String clientType = 'app';

  static const String headerAuthorization = 'Authorization';
  static const String headerClientType = 'X-Client-Type';
  static const String headerClientVersion = 'X-Client-Version';
  static const String headerRequestId = 'X-Request-Id';
}
