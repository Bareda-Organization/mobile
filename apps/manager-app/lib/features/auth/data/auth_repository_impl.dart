import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';

/// [AuthRepository] 의 `data` 계층 구현 — `baraeda_core` 의 [AuthApi] 를
/// 그대로 감싼다. 조립(provider 로 이 클래스를 [AuthRepository] 타입에
/// 묶는 것)은 `app/di.dart` 가 한다 — `presentation` 은 이 파일을 직접
/// import 하지 않고 `app/di.dart` 가 노출하는 provider(타입은 [AuthRepository])
/// 만 본다(CONVENTIONS_FLUTTER.md §2). `parent_app` 의 같은 파일과 내용이
/// 같다(§1.1, 보고서 § 아키텍처 결정 1).
///
/// `AuthApi` 는 실패하면 원시 `DioException` 을 던진다 — 여기서
/// [Failure] 로 옮겨 던지는 것이 이 클래스의 유일한 부가 역할이다.
/// `presentation` 은 `DioException` 을 본 적이 없어야 한다
/// (CONVENTIONS_FLUTTER.md §6).
class AuthRepositoryImpl implements AuthRepository {
  /// [authApi] 를 주입받는다 — 이 클래스는 `AuthApi` 를 만들지 않는다.
  /// 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  /// 쓴다(필드명과 같은 이름의 public named 파라미터를 두면 캡슐화가 깨진다).
  // ignore: prefer_initializing_formals
  const AuthRepositoryImpl({required AuthApi authApi}) : _authApi = authApi;

  final AuthApi _authApi;

  @override
  Future<List<AcademySummary>> searchAcademies(String query) =>
      _guard(() => _authApi.searchAcademies(query));

  @override
  Future<SignupResponse> signup(SignupRequest request) =>
      _guard(() => _authApi.signup(request));

  @override
  Future<SignupStatusResponse> signupStatus() =>
      _guard(_authApi.signupStatus);

  @override
  Future<ReapplyResponse> reapply({required String academyId}) =>
      _guard(() => _authApi.reapply(academyId: academyId));

  @override
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  }) => _guard(() => _authApi.login(loginId: loginId, password: password));

  @override
  Future<void> logout() => _guard(_authApi.logout);

  @override
  Future<MeResponse> me() => _guard(_authApi.me);

  /// `DioException` → [Failure] 변환 지점 하나 — 메서드마다 반복하지 않는다.
  /// `Failure` 는 의도적으로 `Exception`/`Error` 를 상속하지 않는
  /// freezed sealed union 이다(화면은 `on Failure catch` 로 잡아 switch 로
  /// 분기한다) — dart:core 예외 체계를 흉내 내지 않는 설계이므로 이 지점의
  /// `only_throw_errors` 는 예외로 둔다.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on DioException catch (exception) {
      // Failure 는 의도적으로 Exception/Error 를 상속하지 않는다(위 참고).
      // ignore: only_throw_errors
      throw mapDioExceptionToFailure(exception);
    }
  }
}
