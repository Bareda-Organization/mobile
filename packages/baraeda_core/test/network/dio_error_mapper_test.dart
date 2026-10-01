import 'package:baraeda_core/error/failure.dart';
import 'package:baraeda_core/network/dio_error_mapper.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// API_SPEC §1.10 에러 응답 본문 형식 그대로 구성한 badResponse 를 만든다.
DioException _badResponse({
  required int statusCode,
  required Map<String, dynamic> body,
}) {
  final requestOptions = RequestOptions(path: '/students/1');
  return DioException.badResponse(
    statusCode: statusCode,
    requestOptions: requestOptions,
    response: Response<dynamic>(
      requestOptions: requestOptions,
      statusCode: statusCode,
      data: body,
    ),
  );
}

void main() {
  group('mapDioExceptionToFailure — API_SPEC §8 에러 코드', () {
    test('401 TOKEN_EXPIRED 는 재로그인이 필요한 Failure.unauthenticated 로 옮긴다', () {
      // F07-07 — `Failure.unauthenticated` 는 선언만 있고 만들어지는 곳이 없었다.
      // 인터셉터가 재발급까지 실패한 401 을 그대로 던지므로 여기서 옮긴다.
      final exception = _badResponse(
        statusCode: 401,
        body: {
          'error': {'code': 'TOKEN_EXPIRED', 'message': '재로그인이 필요합니다'},
        },
      );

      expect(
        mapDioExceptionToFailure(exception),
        isA<UnauthenticatedFailure>(),
      );
    });

    test('401 INVALID_CREDENTIALS 는 로그인 실패이지 세션 만료가 아니라 Failure.api 로 남긴다', () {
      final exception = _badResponse(
        statusCode: 401,
        body: {
          'error': {'code': 'INVALID_CREDENTIALS', 'message': '불일치'},
        },
      );

      final failure = mapDioExceptionToFailure(exception);

      expect(failure, isA<ApiFailure>());
      expect((failure as ApiFailure).code, 'INVALID_CREDENTIALS');
    });

    test('409 CAPACITY_EXCEEDED 는 details 까지 옮긴다', () {
      final exception = _badResponse(
        statusCode: 409,
        body: {
          'error': {
            'code': 'CAPACITY_EXCEEDED',
            'message': '정원을 초과했습니다',
            'details': {'current': 12, 'capacity': 12},
          },
        },
      );

      final failure = mapDioExceptionToFailure(exception) as ApiFailure;

      expect(failure.code, 'CAPACITY_EXCEEDED');
      expect(failure.details, {'current': 12, 'capacity': 12});
    });

    test('연결 타임아웃은 Failure.network 로 옮긴다', () {
      final requestOptions = RequestOptions(path: '/students/1');
      final exception = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.connectionTimeout,
      );

      expect(mapDioExceptionToFailure(exception), isA<NetworkFailure>());
    });

    test('§1.10 형식이 아닌 본문은 Failure.unknown 으로 옮긴다', () {
      final exception = _badResponse(statusCode: 500, body: {'ok': false});

      expect(mapDioExceptionToFailure(exception), isA<UnknownFailure>());
    });

    // R46-FIXRT S-9 — nginx 가 HTML 로 돌려주는 502·504 는 본문이 §1.10 형식이 아니라 `UnknownFailure` 가 된다.
    // 오프라인 큐가 "서버가 응답하고도 못 받은 5xx" 를 가르려면 상태 코드가 값으로 남아야 한다(문구 파싱 금지).
    test('§1.10 형식이 아닌 본문의 UnknownFailure 는 HTTP 상태를 값으로 싣는다', () {
      final exception = _badResponse(statusCode: 502, body: {'ok': false});

      final failure = mapDioExceptionToFailure(exception);

      expect(failure, isA<UnknownFailure>());
      expect((failure as UnknownFailure).statusCode, 502);
    });

    test('응답이 없는 UnknownFailure(취소)는 상태 코드가 없다', () {
      final exception = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.cancel,
      );

      final failure = mapDioExceptionToFailure(exception);

      expect((failure as UnknownFailure).statusCode, isNull);
    });
  });
}
