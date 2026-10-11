import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:parent_app/core/auth/academy_contact.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';

/// [AuthRepository] 의 `data` 계층 구현 — `baraeda_core` 의 [AuthApi] 를
/// 그대로 감싼다. 조립(provider 로 이 클래스를 [AuthRepository] 타입에
/// 묶는 것)은 `app/di.dart` 가 한다 — `presentation` 은 이 파일을 직접
/// import 하지 않고 `app/di.dart` 가 노출하는 provider(타입은 [AuthRepository])
/// 만 본다(CONVENTIONS_FLUTTER.md §2).
///
/// `AuthApi` 는 실패하면 원시 `DioException` 을 던진다 — 여기서
/// [Failure] 로 옮겨 던지는 것이 이 클래스의 유일한 부가 역할이다.
/// `presentation` 은 `DioException` 을 본 적이 없어야 한다
/// (CONVENTIONS_FLUTTER.md §6).
class AuthRepositoryImpl implements AuthRepository {
  /// [_authApi] 를 주입받는다 — 이 클래스는 `AuthApi` 를 만들지 않는다.
  const new({required this._authApi, required this._contactStorage});

  final AuthApi _authApi;

  /// `/me` 가 알려 준 학원 문의처를 남기는 곳 — 차단 화면과 홈 실패 화면의 전화가 읽는다(R53 t3 A4).
  final AcademyContactStorage _contactStorage;

  @override
  Future<List<AcademySummary>> searchAcademies(String query) =>
      _guard(() => _authApi.searchAcademies(query));

  @override
  Future<SignupResponse> signup(SignupRequest request) =>
      _guard(() => _authApi.signup(request));

  @override
  Future<SignupStatusResponse> signupStatus() => _guard(_authApi.signupStatus);

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
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _guard(
    () => _authApi.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    ),
  );

  @override
  Future<void> recover({
    required String type,
    required String phone,
    String? verificationCode,
  }) => _guard(
    () => _authApi.recover(
      type: type,
      phone: phone,
      verificationCode: verificationCode,
    ),
  );

  @override
  Future<MeResponse> me() => _guard(() async {
    final me = await _authApi.me();
    // 승인 대기 화면을 거치지 않은 계정도 문의처를 알게 한다 — 없으면 이미 남긴 값을 지우지 않는다.
    final contact = me.academy?.contact;
    if (contact != null) await _contactStorage.save(contact);
    return me;
  });

  @override
  Future<DeviceRegistrationResponse> registerDevice(
    DeviceRegistrationRequest request,
  ) => _guard(() => _authApi.registerDevice(request));

  @override
  Future<void> unregisterDevice(String token) =>
      _guard(() => _authApi.unregisterDevice(token));

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
