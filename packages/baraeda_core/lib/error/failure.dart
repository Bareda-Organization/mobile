import 'package:freezed_annotation/freezed_annotation.dart';

part 'failure.freezed.dart';

/// 화면이 보는 에러 타입. `DioException` 을 직접 보지 않고 이 타입만 본다
/// (CONVENTIONS_FLUTTER.md §6). `core/network` 한 곳에서만 이 타입으로 변환한다.
///
/// `api` 는 API_SPEC §1.10 에러 응답 본문(`error.code`·`error.message`·
/// `error.details`)을 그대로 옮긴 것 — 코드마다 별도 하위 타입을 두지 않는다.
/// 코드 사전(§8)이 100개가 넘고 화면마다 반응해야 할 코드가 다르므로,
/// 분기는 화면이 `code` 문자열로 하고 이 타입은 옮기는 역할만 한다.
@freezed
sealed class Failure with _$Failure {
  /// 요청이 서버에 닿지 못함 — 연결 실패 · 타임아웃.
  const factory Failure.network({String? message}) = NetworkFailure;

  /// 서버가 §1.10 형식으로 응답한 에러. `statusCode` 는 HTTP 상태.
  const factory Failure.api({
    required int statusCode,
    required String code,
    required String message,
    Map<String, dynamic>? details,
  }) = ApiFailure;

  /// access 토큰 재발급까지 실패해 재로그인이 필요한 경우
  /// (`TOKEN_EXPIRED` 재시도 실패, §1.2).
  const factory Failure.unauthenticated() = UnauthenticatedFailure;

  /// 위 세 가지로 분류되지 않는 나머지. 서버가 응답했는데 본문이 §1.10 형식이 아니면(nginx 의 HTML 502·504 등)
  /// `statusCode` 가 그 HTTP 상태를 담는다 — 응답이 없었다면 `null`.
  const factory Failure.unknown({String? message, int? statusCode}) =
      UnknownFailure;
}
