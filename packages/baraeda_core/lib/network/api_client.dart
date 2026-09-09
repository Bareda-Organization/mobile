import 'package:baraeda_core/storage/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

/// API_SPEC §1 공통 규약의 헤더 이름 — 두 앱이 같은 값을 쓰므로 이 패키지에
/// 고정한다. 앱마다 달라지는 것은 `baseUrl`·`clientType` 뿐이라
/// `ApiClient` 생성자로 그 둘만 받는다(`api_constants.dart` 는 앱에 남는다).
const _headerAuthorization = 'Authorization';
const _headerClientType = 'X-Client-Type';
const _headerRequestId = 'X-Request-Id';

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
  /// [baseUrl]·[clientType] 은 앱마다 다를 수 있어 주입받는다
  /// (`api_constants.dart` 는 앱에 남아 있다).
  ApiClient({
    required this._tokenStorage,
    required String baseUrl,
    String clientType = 'app',
    Dio? dio,
    Dio? refreshDio,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(baseUrl: baseUrl, contentType: 'application/json'),
           ) {
    // ⚠ refresh 는 **인터셉터가 붙지 않은 별도 인스턴스**로 보낸다.
    // 같은 dio 로 보내면 refresh 응답이 401 일 때 이 인터셉터가 refresh 요청
    // 자신에게 다시 걸려 무한 재귀가 된다 — access·refresh 가 둘 다 만료된
    // 실제 상황이 정확히 그 경우다. 웹(`shared/lib/http/refreshClient.ts`)도
    // 같은 이유로 클라이언트를 분리해 둔다.
    final refresh =
        refreshDio ??
        Dio(BaseOptions(baseUrl: baseUrl, contentType: 'application/json'));
    _dio.interceptors.add(
      _AuthInterceptor(
        _tokenStorage,
        _dio,
        refresh,
        clientType: clientType,
      ),
    );
  }

  final TokenStorage _tokenStorage;
  final Dio _dio;

  /// 인터셉터가 붙은 dio 인스턴스. repository 는 이것으로 요청한다.
  Dio get dio => _dio;
}

/// 요청마다 access 토큰 · 공통 헤더를 붙이고, `401` 을 받으면 refresh 후
/// 원 요청을 **한 번만** 재시도한다. 재시도까지 실패하면 그대로 던져
/// `dio_error_mapper.dart` 가 `Failure.unauthenticated()` 로 옮기게 둔다.
class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(
    this._tokenStorage,
    this._dio,
    this._refreshDio, {
    required this.clientType,
  });

  final TokenStorage _tokenStorage;
  final Dio _dio;

  /// 인터셉터가 붙지 않은 인스턴스 — refresh 응답이 401 일 때
  /// 이 인터셉터가 자기 자신에게 다시 걸리는 것을 구조적으로 막는다.
  final Dio _refreshDio;
  final String clientType;

  static const _retriedKey = 'retried_after_refresh';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken != null) {
      options.headers[_headerAuthorization] = 'Bearer $accessToken';
    }
    options.headers[_headerClientType] = clientType;
    options.headers[_headerRequestId] = IdempotencyKeys.generate();
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
      final refreshResponse = await _refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(headers: {_headerClientType: clientType}),
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
        ..headers[_headerAuthorization] = 'Bearer $newAccessToken'
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
  /// UUID v4 문자열 하나를 새로 발급한다.
  static String generate() => _uuid.v4();

  static const _uuid = Uuid();
}
