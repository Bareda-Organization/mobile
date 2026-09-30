import 'dart:async';

import 'package:baraeda_core/network/token_refresher.dart';
import 'package:baraeda_core/storage/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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

/// 음영 구간에서 요청이 무기한 매달리지 않게 하는 제한 시간. dio 5 의 기본은 제한 없음이라
/// 재발급 하나가 멈추면 그 결과에 합류한 모든 요청과 WS 재연결이 같이 멈춘다.
const _connectTimeout = Duration(seconds: 10);
const _sendTimeout = Duration(seconds: 15);
const _receiveTimeout = Duration(seconds: 30);

Dio _newDio(String baseUrl) => Dio(
  BaseOptions(
    baseUrl: baseUrl,
    contentType: 'application/json',
    connectTimeout: _connectTimeout,
    sendTimeout: _sendTimeout,
    receiveTimeout: _receiveTimeout,
  ),
);

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
  }) : _dio = dio ?? _newDio(baseUrl) {
    // ⚠ refresh 는 **인터셉터가 붙지 않은 별도 인스턴스**로 보낸다.
    // 같은 dio 로 보내면 refresh 응답이 401 일 때 이 인터셉터가 refresh 요청
    // 자신에게 다시 걸려 무한 재귀가 된다 — access·refresh 가 둘 다 만료된
    // 실제 상황이 정확히 그 경우다. 웹(`shared/lib/http/refreshClient.ts`)도
    // 같은 이유로 클라이언트를 분리해 둔다.
    final refresh = _refreshDio = refreshDio ?? _newDio(baseUrl);
    // 봉투 해제는 `_dio` · `refresh` 양쪽에 붙인다 — 한 곳(이 생성자)에서만
    // 등록해 두면 이후 이 클래스를 거쳐 나가는 요청이 하나 더 생겨도 저절로
    // 적용된다(API_SPEC §1.1: 성공 응답은 전부 `{success, data, message}`로
    // 감싸져 있고, `/auth/refresh` 응답도 예외가 아니다).
    _dio.interceptors.add(_EnvelopeInterceptor());
    refresh.interceptors.add(_EnvelopeInterceptor());
    // WS 클라이언트(`BaraedaWebSocketClient`)도 이 인스턴스를 그대로 받는다
    // (`tokenRefresher` getter) — REST·WS 동시 재발급 경합을 막는 이유는
    // `token_refresher.dart` 문서를 본다.
    tokenRefresher = TokenRefresher(
      refreshDio: refresh,
      tokenStorage: _tokenStorage,
      clientType: clientType,
    );
    _dio.interceptors.add(
      _AuthInterceptor(
        _tokenStorage,
        _dio,
        tokenRefresher,
        clientType: clientType,
        gateEvents: _gateEventsController,
      ),
    );
  }

  final TokenStorage _tokenStorage;
  final Dio _dio;
  late final Dio _refreshDio;
  final _gateEventsController = StreamController<AccountGateReason>.broadcast();

  /// 인터셉터가 붙은 dio 인스턴스. repository 는 이것으로 요청한다.
  Dio get dio => _dio;

  /// REST 401 재발급과 WS 재발급이 공유하는 창구 — 앱의 WS 클라이언트
  /// 생성 지점(`di.dart` 등)이 이 값의 [TokenRefresher.refresh] 를 그대로
  /// 넘겨 받는다.
  late final TokenRefresher tokenRefresher;

  /// `403 AUTH_PENDING`·`403 AUTH_REJECTED` 를 어느 화면의 어느 호출이
  /// 냈든 한 곳(인터셉터)에서 감지해 흘려보내는 스트림. 라우터가 이것만
  /// 구독하면 화면마다 게이트 분기를 따로 심을 필요가 없다(목표 7항).
  Stream<AccountGateReason> get gateEvents => _gateEventsController.stream;

  /// refresh 토큰이 거절돼(401) 재로그인이 필요해졌을 때 한 번 흘러가는 신호 — REST 경로의
  /// 세션 만료 신호다(WS 는 `BaraedaWebSocketClient.sessionExpired`). 앱의 세션 관리자가
  /// 이것을 구독해 로그인 화면으로 보낸다. 네트워크 오류·5xx 는 이 신호를 내지 않는다.
  Stream<void> get sessionExpired => tokenRefresher.sessionInvalidated;

  /// 재발급 전용 dio(인터셉터 없음) — 기본 제한 시간 시험이 읽는다.
  @visibleForTesting
  Dio get refreshDio => _refreshDio;

  /// 앱 종료 시 호출 — 테스트에서도 `StreamController` 누수를 막기 위해 부른다.
  void dispose() {
    unawaited(_gateEventsController.close());
    tokenRefresher.dispose();
  }
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
/// 원 요청을 **한 번만** 재시도한다. 재발급을 서버가 거절하면(세션 종료) 원 401 을 그대로
/// 던져 `dio_error_mapper.dart` 가 `Failure.unauthenticated()` 로 옮기게 두고 재로그인
/// 신호는 [ApiClient.sessionExpired] 가 낸다. 재발급·재시도가 일시 장애로 실패하면 그 오류를
/// 그대로 던지고 토큰은 지우지 않는다.
class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(
    this._tokenStorage,
    this._dio,
    this._tokenRefresher, {
    required this.clientType,
    required this._gateEvents,
  });

  final TokenStorage _tokenStorage;
  final Dio _dio;

  /// REST·WS 가 공유하는 재발급 창구 — `token_refresher.dart` 문서 참고.
  final TokenRefresher _tokenRefresher;
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

    // 실제 HTTP 호출·저장·실패 시 토큰 삭제는 `TokenRefresher` 가 한다 —
    // WS 클라이언트와 같은 창구를 공유해야 동시 재발급 경합이 없다
    // (`token_refresher.dart` 문서).
    final String? newAccessToken;
    try {
      newAccessToken = await _tokenRefresher.refresh();
    } on DioException catch (refreshError) {
      // 재발급 요청 자체가 실패했다(연결 실패·타임아웃·5xx) — 세션은 살아 있을 수 있어
      // 토큰은 그대로 두고, 화면에는 옛 401 이 아니라 실제 실패 원인을 돌려준다.
      handler.next(
        DioException(
          requestOptions: err.requestOptions,
          type: refreshError.type,
          response: refreshError.response,
          error: refreshError.error,
          message: refreshError.message,
        ),
      );
      return;
    }
    if (newAccessToken == null) {
      handler.next(err);
      return;
    }

    try {
      final retryOptions = err.requestOptions
        ..headers[_headerAuthorization] = 'Bearer $newAccessToken'
        ..extra[_retriedKey] = true;
      final retryResponse = await _dio.fetch<dynamic>(retryOptions);
      handler.resolve(retryResponse);
    } on DioException catch (retryError) {
      // 재발급에 성공했으니 세션은 유효하다 — 토큰을 지우지 않고 재시도의 실제 오류
      // (409 업무 오류·5xx·연결 끊김 등)를 그대로 넘긴다.
      handler.next(retryError);
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
