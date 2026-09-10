import 'package:baraeda_core/baraeda_core.dart';

/// 화면이 보는 인증 계약. `presentation` 은 이 인터페이스만 알고
/// `baraeda_core` 의 `AuthApi`(`data`)를 직접 보지 않는다
/// (CONVENTIONS_FLUTTER.md §2 의존 방향).
///
/// 메서드 이름·시그니처는 `AuthApi` 를 그대로 옮긴 것이 아니라 이 앱
/// 화면이 실제로 필요로 하는 것만 추린다 — §2.11 기기 등록처럼 화면이
/// 아직 안 쓰는 것은 여기 노출하지 않는다. `parent_app` 의 같은 파일과
/// 내용이 같다 — 인증 데이터 계약은 역할과 무관하다(§1.1, 보고서 § 아키텍처
/// 결정 1: 데이터 계층은 `baraeda_core` 하나, 이 인터페이스만 앱마다 얇게 둔다).
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

  /// §2.9. 자동 로그인 부트스트랩(`account_session.dart`)과 로그인 성공
  /// 직후 역할·상태 확인에 쓴다.
  Future<MeResponse> me();
}
