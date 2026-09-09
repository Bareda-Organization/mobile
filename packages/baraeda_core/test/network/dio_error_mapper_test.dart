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
    test('401 TOKEN_EXPIRED 를 Failure.api 로 코드까지 그대로 옮긴다', () {
      final exception = _badResponse(
        statusCode: 401,
        body: {
          'error': {'code': 'TOKEN_EXPIRED', 'message': '재로그인이 필요합니다'},
        },
      );

      final failure = mapDioExceptionToFailure(exception);

      expect(failure, isA<ApiFailure>());
      final api = failure as ApiFailure;
      expect(api.statusCode, 401);
      expect(api.code, 'TOKEN_EXPIRED');
      expect(api.message, '재로그인이 필요합니다');
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
  });
}
