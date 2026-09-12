import 'package:baraeda_core/baraeda_core.dart';

/// 화면이 보는 인증 계약. `presentation` 은 이 인터페이스만 알고
/// `baraeda_core` 의 `AuthApi`(`data`)를 직접 보지 않는다
/// (CONVENTIONS_FLUTTER.md §2 의존 방향).
///
/// 메서드 이름·시그니처는 `AuthApi` 를 그대로 옮긴 것이 아니라 이 앱
/// 화면이 실제로 필요로 하는 것만 추린다.
///
/// `core/auth` 에 두는 이유 — 처음엔 `features/auth` 소유였으나,
/// `features/settings`(비밀번호 변경·계정 복구·단말 등록)도 이 계약이
/// 필요해져 2개 feature 가 공유하게 됐다(`core/students`·`core/runs` 와
/// 같은 승격 기준, CONVENTIONS_FLUTTER.md §2).
abstract interface class AuthRepository {
  /// §2.1.
  Future<List<AcademySummary>> searchAcademies(String query);

  /// §2.2. 실패하면 `dio_error_mapper` 를 거친 [Failure] 를 던진다.
  Future<SignupResponse> signup(SignupRequest request);

  /// §2.3.
  Future<SignupStatusResponse> signupStatus();

  /// §2.4.
  Future<ReapplyResponse> reapply({required String academyId});

  /// §2.5. 성공하면 토큰이 저장된 뒤 응답을 그대로 돌려준다(`AuthApi.login`
  /// 이 이미 저장까지 한다).
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  });

  /// §2.7.
  Future<void> logout();

  /// §2.8 — 비밀번호 변경. 성공하면 서버가 기존 refresh 토큰을 전량
  /// 무효화한다 — 로컬 토큰을 지우고 재로그인 화면으로 보내는 판단은
  /// 화면(`password_change_screen.dart`)의 몫이다.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// §2.9 — 비인증(로그인 화면에서 진입). `verificationCode` 를 생략하면
  /// SMS 발송 요청으로 처리된다.
  Future<void> recover({
    required String type,
    required String phone,
    String? verificationCode,
  });

  /// §2.10. 자동 로그인 부트스트랩(`account_session.dart`)과 로그인 성공
  /// 직후 역할·상태 확인에 쓴다.
  Future<MeResponse> me();

  /// §2.11 등록 — `pending` 계정도 호출 가능(§1.4 허용 목록).
  Future<DeviceRegistrationResponse> registerDevice(
    DeviceRegistrationRequest request,
  );

  /// §2.11 해지.
  Future<void> unregisterDevice(String token);
}
