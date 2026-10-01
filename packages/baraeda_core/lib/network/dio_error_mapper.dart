import 'package:baraeda_core/error/failure.dart';
import 'package:dio/dio.dart';

/// `DioException` → `Failure` 변환을 한 곳에 모은다 (CONVENTIONS_FLUTTER.md §6).
/// 화면·repository 는 이 함수를 거친 `Failure` 만 본다.
Failure mapDioExceptionToFailure(DioException exception) {
  switch (exception.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
    case DioExceptionType.transformTimeout:
      return Failure.network(message: exception.message);
    case DioExceptionType.badCertificate:
      return const Failure.network(message: '인증서 검증 실패');
    case DioExceptionType.cancel:
      return const Failure.unknown(message: '요청이 취소됨');
    case DioExceptionType.badResponse:
      return _mapBadResponse(exception);
    case DioExceptionType.unknown:
      return Failure.unknown(message: exception.message);
  }
}

Failure _mapBadResponse(DioException exception) {
  final statusCode = exception.response?.statusCode;
  final body = exception.response?.data;

  // API_SPEC §1.10 — { "error": { "code", "message", "details" } }
  if (body is Map<String, dynamic> && body['error'] is Map<String, dynamic>) {
    final error = body['error'] as Map<String, dynamic>;
    // API_SPEC §8 — 재발급까지 실패해 재로그인이 필요한 401. 로그인 실패(`INVALID_CREDENTIALS`)
    // 같은 다른 401 은 업무 오류로 남긴다.
    if (statusCode == 401 && error['code'] == 'TOKEN_EXPIRED') {
      return const Failure.unauthenticated();
    }
    return Failure.api(
      statusCode: statusCode ?? 0,
      code: error['code'] as String? ?? 'UNKNOWN',
      message: error['message'] as String? ?? '알 수 없는 오류가 발생했습니다',
      details: error['details'] as Map<String, dynamic>?,
    );
  }

  return Failure.unknown(
    message: '서버 응답을 해석할 수 없음 (status: $statusCode)',
    statusCode: statusCode,
  );
}
