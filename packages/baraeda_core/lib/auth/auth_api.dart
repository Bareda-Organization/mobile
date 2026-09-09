import 'package:baraeda_core/auth/models/academy_summary.dart';
import 'package:baraeda_core/auth/models/device_registration.dart';
import 'package:baraeda_core/auth/models/login_response.dart';
import 'package:baraeda_core/auth/models/me_response.dart';
import 'package:baraeda_core/auth/models/reapply_response.dart';
import 'package:baraeda_core/auth/models/signup_models.dart';
import 'package:baraeda_core/auth/models/signup_status_response.dart';
import 'package:baraeda_core/storage/token_storage.dart';
import 'package:dio/dio.dart';

/// API_SPEC §2 인증 엔드포인트 11개(§2.6 `/auth/refresh` 는 `ApiClient` 의
/// 인터셉터가 내부적으로만 쓰므로 이 클래스가 노출하지 않는다)를 한 곳에
/// 모은다. 두 앱이 화면·역할 vocabulary 는 다르지만 이 프로토콜 자체는
/// 같으므로 `baraeda_core` 에 두고 앱마다 두 벌 만들지 않는다(§ 아키텍처
/// 결정 1, 보고서 참고).
///
/// 응답은 `ApiClient` 의 `_EnvelopeInterceptor` 가 이미 `data` 봉투를 벗긴
/// 뒤라 여기서는 각 응답의 필드만 그대로 읽는다.
class AuthApi {
  /// `dio` 는 `ApiClient.dio`(인터셉터 부착된 인스턴스)를 그대로 받는다.
  AuthApi({required this._dio, required this._tokenStorage});

  final Dio _dio;
  final TokenStorage _tokenStorage;

  /// §2.1 — 비인증. 검색어가 비어 있으면 서버가 `422` 를 던진다.
  Future<List<AcademySummary>> searchAcademies(String query) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/academies/search',
      queryParameters: {'q': query},
    );
    final items = response.data?['items'] as List<dynamic>? ?? [];
    return items
        .cast<Map<String, dynamic>>()
        .map(AcademySummary.fromJson)
        .toList();
  }

  /// §2.2 — 비인증. 성공해도 토큰은 발급되지 않는다(계정이 `pending` 으로
  /// 생성될 뿐 로그인이 아니다).
  Future<SignupResponse> signup(SignupRequest request) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/signup',
      data: request.toJson(),
    );
    return SignupResponse.fromJson(response.data!);
  }

  /// §2.3 — `pending`·`rejected` 토큰으로도 호출 가능.
  Future<SignupStatusResponse> signupStatus() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/auth/signup-status',
    );
    return SignupStatusResponse.fromJson(response.data!);
  }

  /// §2.4 — `rejected` 계정만 호출 가능.
  Future<ReapplyResponse> reapply({required String academyId}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/signup/reapply',
      data: {'academy_id': academyId},
    );
    return ReapplyResponse.fromJson(response.data!);
  }

  /// §2.5 — 비인증. `pending`·`rejected` 도 토큰을 발급받으므로 로그인
  /// 자체는 항상 성공 응답이면 토큰을 저장한다(접근 범위 축소는 §1.4 로
  /// 서버가 이후 요청에서 걸고, 그 신호는 `ApiClient.gateEvents` 가 옮긴다).
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'login_id': loginId, 'password': password},
    );
    final loginResponse = LoginResponse.fromJson(response.data!);
    final refreshToken = loginResponse.refreshToken;
    if (refreshToken != null) {
      await _tokenStorage.saveTokens(
        accessToken: loginResponse.accessToken,
        refreshToken: refreshToken,
      );
    }
    return loginResponse;
  }

  /// §2.7 — 저장된 refresh 토큰을 본문에 실어 서버 쪽을 무효화하고,
  /// 서버 호출 성패와 무관하게 로컬 토큰은 항상 지운다 — 로그아웃 버튼을
  /// 누른 사용자가 네트워크 실패로 로그인 상태에 갇히면 안 된다.
  Future<void> logout() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    try {
      await _dio.post<void>(
        '/auth/logout',
        data: {'refresh_token': refreshToken},
      );
    } finally {
      await _tokenStorage.clear();
    }
  }

  /// §2.8. 성공하면 서버가 기존 refresh 토큰을 전량 무효화한다 — 화면은
  /// 이 호출이 끝나면 재로그인 화면으로 보내야 한다(이 메서드는 로컬 토큰을
  /// 지우지 않는다: 그 판단은 화면의 몫이다).
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _dio.post<void>(
      '/auth/password',
      data: {
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
  }

  /// §2.9 — 비인증. `verificationCode` 를 생략하면 SMS 발송 요청으로
  /// 처리된다.
  Future<void> recover({
    required String type,
    required String phone,
    String? verificationCode,
  }) async {
    await _dio.post<void>(
      '/auth/recover',
      data: {
        'type': type,
        'phone': phone,
        'verification_code': ?verificationCode,
      },
    );
  }

  /// §2.10 — 전 역할 공통, `pending`·`rejected` 도 호출 가능. 앱 재실행 시
  /// `role`·`status` 를 다시 얻는 유일한 경로(§2.10 이유 ②).
  Future<MeResponse> me() async {
    final response = await _dio.get<Map<String, dynamic>>('/me');
    return MeResponse.fromJson(response.data!);
  }

  /// §2.11 등록.
  Future<DeviceRegistrationResponse> registerDevice(
    DeviceRegistrationRequest request,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/me/devices',
      data: request.toJson(),
    );
    return DeviceRegistrationResponse.fromJson(response.data!);
  }

  /// §2.11 해지.
  Future<void> unregisterDevice(String token) async {
    await _dio.delete<void>('/me/devices/$token');
  }
}
