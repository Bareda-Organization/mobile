import 'package:dio/dio.dart';
import 'package:manager_app/core/constants/api_constants.dart';
import 'package:manager_app/core/storage/token_storage.dart';
import 'package:uuid/uuid.dart';

/// API_SPEC §1 공통 규약을 한곳에서 처리하는 dio 설정.
///
/// - access 토큰 부착, `401 TOKEN_EXPIRED` 시 `/auth/refresh` 후 **1회만** 재시도 (§1.2)
/// - `X-Client-Type: app` 부착 (§1.3)
/// - `X-Request-Id` 부착 — 미부착 시 서버가 생성하므로 필수는 아니나,
///   클라이언트 로그와 서버 로그를 같은 값으로 엮기 위해 매 요청 부착
///
/// ⚠ 멱등 키(`client_key`, §1.7)는 헤더가 아니라 **요청 본문 필드**라 여기서
/// 다루지 않는다 — 그 값을 채우는 곳은 승하차 처리 · 비상 발신을 호출하는
/// repository 쪽이다(`IdempotencyKeys.generate()` 만 이 파일이 제공).
class ApiClient {
  ApiClient({required this._tokenStorage, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: ApiConstants.baseUrl,
              contentType: 'application/json',
            ),
          ) {
    _dio.interceptors.add(_AuthInterceptor(_tokenStorage, _dio));
  }

  final TokenStorage _tokenStorage;
  final Dio _dio;

  Dio get dio => _dio;
}

/// 요청마다 access 토큰 · 공통 헤더를 붙이고, `401` 을 받으면 refresh 후
/// 원 요청을 **한 번만** 재시도한다. 재시도까지 실패하면 그대로 던져
/// `dio_error_mapper.dart` 가 `Failure.unauthenticated()` 로 옮기게 둔다.
class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._tokenStorage, this._dio);

  final TokenStorage _tokenStorage;
  final Dio _dio;

  static const _retriedKey = 'retried_after_refresh';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken != null) {
      options.headers[ApiConstants.headerAuthorization] = 'Bearer $accessToken';
    }
    options.headers[ApiConstants.headerClientType] = ApiConstants.clientType;
    options.headers[ApiConstants.headerRequestId] = IdempotencyKeys.generate();
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final alreadyRetried = err.requestOptions.extra[_retriedKey] == true;

    if (response?.statusCode != 401 || alreadyRetried) {
      handler.next(err);
      return;
    }

    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null) {
      handler.next(err);
      return;
    }

    try {
      final refreshResponse = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(
          headers: {ApiConstants.headerClientType: ApiConstants.clientType},
        ),
      );
      final body = refreshResponse.data;
      final newAccessToken = body?['access_token'] as String?;
      final newRefreshToken = body?['refresh_token'] as String?;
      if (newAccessToken == null || newRefreshToken == null) {
        handler.next(err);
        return;
      }
      await _tokenStorage.saveTokens(
        accessToken: newAccessToken,
        refreshToken: newRefreshToken,
      );

      final retryOptions = err.requestOptions
        ..headers[ApiConstants.headerAuthorization] = 'Bearer $newAccessToken'
        ..extra[_retriedKey] = true;
      final retryResponse = await _dio.fetch<dynamic>(retryOptions);
      handler.resolve(retryResponse);
    } on DioException {
      await _tokenStorage.clear();
      handler.next(err);
    }
  }
}

/// `client_key`(§1.7) · `X-Request-Id`(§1.3) 로 쓸 단말 발급 UUID.
abstract final class IdempotencyKeys {
  static String generate() => _uuid.v4();

  static const _uuid = Uuid();
}
