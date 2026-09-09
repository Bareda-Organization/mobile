/// API_SPEC §1 공통 규약에서 앱이 직접 참조하는 상수만 모은다.
abstract final class ApiConstants {
  /// API_SPEC §1.1 — 기본 경로는 `/api/v1`. 로컬 개발 기본값이며
  /// 배포 값은 `--dart-define=API_BASE_URL=...` 로 주입한다.
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/api/v1',
  );

  /// API_SPEC §1.3 — 미전달 시 기본값이 `app` 이지만, 앱은 항상 명시한다.
  static const clientType = 'app';

  static const headerAuthorization = 'Authorization';
  static const headerClientType = 'X-Client-Type';
  static const headerRequestId = 'X-Request-Id';
}
