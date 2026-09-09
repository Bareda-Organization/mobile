import 'dart:async';

import 'package:baraeda_core/storage/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

/// API_SPEC §1 공통 규약의 헤더 이름 — 두 앱이 같은 값을 쓰므로 이 패키지에
/// 고정한다. 앱마다 달라지는 것은 `baseUrl`·`clientType` 뿐이라
/// `ApiClient` 생성자로 그 둘만 받는다(`api_constants.dart` 는 앱에 남는다).
const _headerAuthorization = 'Authorization';
const _headerClientType = 'X-Client-Type';
const _headerRequestId = 'X-Request-Id';

/// `403 AUTH_PENDING`·`403 AUTH_REJECTED` 로 계정 상태 게이트에 걸렸다는 신호
/// (API_SPEC §1.4·§1.11). 화면이 어디든 이 값을 받으면 대기 화면으로 보낸다.
enum AccountGateReason {
  /// 승인 대기 중.
  pending,

  /// 거절됨 — 대기 화면이 거절 사유를 추가로 보여준다.
  rejected,
}

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
    // 봉투 해제는 `_dio` · `refresh` 양쪽에 붙인다 — 한 곳(이 생성자)에서만
    // 등록해 두면 이후 이 클래스를 거쳐 나가는 요청이 하나 더 생겨도 저절로
    // 적용된다(API_SPEC §1.1: 성공 응답은 전부 `{success, data, message}`로
    // 감싸져 있고, `/auth/refresh` 응답도 예외가 아니다).
    _dio.interceptors.add(_EnvelopeInterceptor());
    refresh.interceptors.add(_EnvelopeInterceptor());
    _dio.interceptors.add(
      _AuthInterceptor(
        _tokenStorage,
        _dio,
        refresh,
        clientType: clientType,
        gateEvents: _gateEventsController,
      ),
    );
  }

  final TokenStorage _tokenStorage;
  final Dio _dio;
  final _gateEventsController =
      StreamController<AccountGateReason>.broadcast();

  /// 인터셉터가 붙은 dio 인스턴스. repository 는 이것으로 요청한다.
  Dio get dio => _dio;

  /// `403 AUTH_PENDING`·`403 AUTH_REJECTED` 를 어느 화면의 어느 호출이
  /// 냈든 한 곳(인터셉터)에서 감지해 흘려보내는 스트림. 라우터가 이것만
  /// 구독하면 화면마다 게이트 분기를 따로 심을 필요가 없다(목표 7항).
  Stream<AccountGateReason> get gateEvents => _gateEventsController.stream;

  /// 앱 종료 시 호출 — 테스트에서도 `StreamController` 누수를 막기 위해 부른다.
  void dispose() => _gateEventsController.close();
}

/// 성공 응답 봉투를 벗기는 인터셉터.
///
/// 서버는 2xx 응답을 `{"success": true, "data": {...}, "message": null}` 로
/// 감싸 보낸다(API_SPEC §1.1) — 문서화된 필드는 전부 `data` 안에 있다.
/// 에러 응답(`{"error": {...}}`)은 감싸지 않으므로 `onError` 는 건드리지
/// 않는다 — 에러 바디는 `dio_error_mapper.dart` 가 그대로(루트에서) 읽는다.
class _EnvelopeInterceptor extends Interceptor {
  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final body = response.data;
    if (body is Map<String, dynamic> &&
        body.containsKey('success') &&
        body.containsKey('data')) {
      response.data = body['data'];
    }
    handler.next(response);
  }
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
    required this._gateEvents,
  });

  final TokenStorage _tokenStorage;
  final Dio _dio;

  /// 인터셉터가 붙지 않은 인스턴스 — refresh 응답이 401 일 때
  /// 이 인터셉터가 자기 자신에게 다시 걸리는 것을 구조적으로 막는다.
  final Dio _refreshDio;
  final String clientType;
  final StreamController<AccountGateReason> _gateEvents;

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
    _emitGateEventIfAny(err);

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
      // 이 응답은 `_refreshDio` 에 붙은 `_EnvelopeInterceptor` 를 이미 거쳐
      // `data` 봉투가 벗겨진 상태다 — 그래서 아래는 루트에서 바로 읽는다.
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

  /// 이 호출이 어느 화면에서 나갔든 `403 AUTH_PENDING`·`403 AUTH_REJECTED` 를
  /// 여기 한 곳에서만 감지해 [_gateEvents] 로 흘려보낸다 — 화면마다 상태
  /// 분기를 따로 심으면 새 화면을 추가할 때마다 그 분기를 잊을 수 있다.
  void _emitGateEventIfAny(DioException err) {
    final response = err.response;
    if (response?.statusCode != 403) return;
    final body = response?.data;
    if (body is! Map<String, dynamic>) return;
    final error = body['error'];
    if (error is! Map<String, dynamic>) return;
    switch (error['code']) {
      case 'AUTH_PENDING':
        _gateEvents.add(AccountGateReason.pending);
      case 'AUTH_REJECTED':
        _gateEvents.add(AccountGateReason.rejected);
    }
  }
}

/// `client_key`(§1.7) · `X-Request-Id`(§1.3) 로 쓸 단말 발급 UUID.
abstract final class IdempotencyKeys {
  /// UUID v4 문자열 하나를 새로 발급한다.
  static String generate() => _uuid.v4();

  static const _uuid = Uuid();
}
