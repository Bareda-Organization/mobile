/// 화면이 보는 에러 타입. `DioException` 을 직접 보지 않고 이 타입만 본다
/// (CONVENTIONS_FLUTTER.md §6). `core/network` 한 곳에서만 이 타입으로 변환한다.
///
/// `api` 는 API_SPEC §1.10 에러 응답 본문(`error.code`·`error.message`·
/// `error.details`)을 그대로 옮긴 것 — 코드마다 별도 하위 타입을 두지 않는다.
/// 코드 사전(§8)이 100개가 넘고 화면마다 반응해야 할 코드가 다르므로,
/// 분기는 화면이 `code` 문자열로 하고 이 타입은 옮기는 역할만 한다.
sealed class Failure {
  const new();

  /// 요청이 서버에 닿지 못함 — 연결 실패 · 타임아웃.
  const factory network({String? message}) = NetworkFailure;

  /// 서버가 §1.10 형식으로 응답한 에러. `statusCode` 는 HTTP 상태.
  const factory api({
    required int statusCode,
    required String code,
    required String message,
    Map<String, dynamic>? details,
  }) = ApiFailure;

  /// access 토큰 재발급까지 실패해 재로그인이 필요한 경우
  /// (`TOKEN_EXPIRED` 재시도 실패, §1.2).
  const factory unauthenticated() = UnauthenticatedFailure;

  /// 위 세 가지로 분류되지 않는 나머지. 서버가 응답했는데 본문이 §1.10 형식이 아니면(nginx 의 HTML 502·504 등)
  /// `statusCode` 가 그 HTTP 상태를 담는다 — 응답이 없었다면 `null`.
  const factory unknown({String? message, int? statusCode}) = UnknownFailure;
}

/// 요청이 서버에 닿지 못한 경우 — [Failure.network].
final class NetworkFailure extends Failure {
  /// 값을 그대로 받는다.
  const new({this.message});

  /// 원인 설명 — 없을 수 있다.
  final String? message;

  @override
  String toString() => 'Failure.network(message: $message)';
}

/// 서버가 §1.10 형식으로 응답한 에러 — [Failure.api].
final class ApiFailure extends Failure {
  /// 값을 그대로 받는다.
  const new({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details,
  });

  /// HTTP 상태.
  final int statusCode;

  /// 에러 코드 사전(API_SPEC §8)의 코드.
  final String code;

  /// 서버가 보낸 사용자용 메시지.
  final String message;

  /// 필드별 상세 — 없을 수 있다.
  final Map<String, dynamic>? details;

  @override
  String toString() =>
      'Failure.api(statusCode: $statusCode, code: $code, message: $message, '
      'details: $details)';
}

/// 재발급까지 실패해 재로그인이 필요한 경우 — [Failure.unauthenticated].
final class UnauthenticatedFailure extends Failure {
  /// 값 없음.
  const new();

  @override
  String toString() => 'Failure.unauthenticated()';
}

/// 위 세 가지로 분류되지 않는 나머지 — [Failure.unknown].
final class UnknownFailure extends Failure {
  /// 값을 그대로 받는다.
  const new({this.message, this.statusCode});

  /// 원인 설명 — 없을 수 있다.
  final String? message;

  /// 서버가 응답했다면 그 HTTP 상태, 응답이 없었다면 `null`.
  final int? statusCode;

  @override
  String toString() =>
      'Failure.unknown(message: $message, statusCode: $statusCode)';
}
