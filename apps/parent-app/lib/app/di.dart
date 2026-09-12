import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/core/auth/data/auth_repository_impl.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/core/change_requests/data/change_request_api.dart';
import 'package:parent_app/core/change_requests/data/change_request_repository_impl.dart';
import 'package:parent_app/core/change_requests/domain/change_request_repository.dart';
import 'package:parent_app/core/constants/api_constants.dart';
import 'package:parent_app/core/runs/data/run_api.dart';
import 'package:parent_app/core/runs/data/run_repository_impl.dart';
import 'package:parent_app/core/runs/domain/run_repository.dart';
import 'package:parent_app/core/students/data/student_api.dart';
import 'package:parent_app/core/students/data/student_repository_impl.dart';
import 'package:parent_app/core/students/domain/student_repository.dart';
import 'package:parent_app/features/child_link/data/link_api.dart';
import 'package:parent_app/features/child_link/data/link_repository_impl.dart';
import 'package:parent_app/features/child_link/domain/link_repository.dart';
import 'package:parent_app/features/home/data/notification_api.dart';
import 'package:parent_app/features/home/data/notification_repository_impl.dart';
import 'package:parent_app/features/home/domain/notification_repository.dart';
import 'package:parent_app/features/schedule/data/weekly_address_api.dart';
import 'package:parent_app/features/schedule/data/weekly_address_repository_impl.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_repository.dart';
import 'package:parent_app/features/settings/data/device_registration_storage.dart';
import 'package:parent_app/features/settings/data/notification_settings_api.dart';
import 'package:parent_app/features/settings/data/notification_settings_repository_impl.dart';
import 'package:parent_app/features/settings/domain/notification_settings_repository.dart';

/// 앱 전역 의존성 조립 지점. `features/*/data` 는 이 provider 들을 거쳐
/// `ApiClient` 를 받는다 — 전역 싱글턴을 직접 참조하지 않는다
/// (CONVENTIONS_FLUTTER.md §1, Riverpod 채택 이유).
///
/// `ApiClient`·`TokenStorage` 는 `baraeda_core` 패키지로 이동했다 — 앱마다
/// 달라지는 값(저장 키·`baseUrl`·`clientType`)만 여기서 주입한다.

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => TokenStorage(
    accessTokenKey: 'access_token',
    refreshTokenKey: 'refresh_token',
  ),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  // ApiConstants.clientType 은 항상 'app' 이라 ApiClient 의 기본값과 같다
  // (avoid_redundant_argument_values) — 값이 갈릴 일이 생기면 그때 명시한다.
  final client = ApiClient(
    tokenStorage: ref.watch(tokenStorageProvider),
    baseUrl: ApiConstants.baseUrl,
  );
  ref.onDispose(client.dispose);
  return client;
});

/// API_SPEC §2 인증 엔드포인트 — `ApiClient.dio`(인터셉터 부착)를 그대로
/// 물려받는다. `AuthApi` 자체는 `baraeda_core` 소유라 두 앱이 이 provider 만
/// 각자 만든다.
final authApiProvider = Provider<AuthApi>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AuthApi(
    dio: apiClient.dio,
    tokenStorage: ref.watch(tokenStorageProvider),
  );
});

/// `authApiProvider`(data)를 [AuthRepository](domain 인터페이스)에 묶는
/// 조립 지점 — `di.dart` 는 앱의 합성 루트라 계층 전부를 알 수 있다.
/// `features/auth/presentation` 화면은 이 provider 만 참조하고
/// `AuthApi`·`AuthRepositoryImpl` 은 직접 import 하지 않는다
/// (CONVENTIONS_FLUTTER.md §2 "presentation 이 data 를 직접 import 하지 않음").
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(authApi: ref.watch(authApiProvider));
});

/// API_SPEC §3.1 — `home`·`schedule` 공통(`core/students`).
final studentApiProvider = Provider<StudentApi>((ref) {
  return StudentApi(dio: ref.watch(apiClientProvider).dio);
});

final studentRepositoryProvider = Provider<StudentRepository>((ref) {
  return StudentRepositoryImpl(studentApi: ref.watch(studentApiProvider));
});

/// API_SPEC §3.5·§3.6 — `home`·`schedule` 공통(`core/runs`, 변경 신청이
/// 회차를 참조하므로 두 feature 가 함께 쓴다).
final runApiProvider = Provider<RunApi>((ref) {
  return RunApi(dio: ref.watch(apiClientProvider).dio);
});

final runRepositoryProvider = Provider<RunRepository>((ref) {
  return RunRepositoryImpl(runApi: ref.watch(runApiProvider));
});

/// API_SPEC §3.12·§3.13 — `home`.
final notificationApiProvider = Provider<NotificationApi>((ref) {
  return NotificationApi(dio: ref.watch(apiClientProvider).dio);
});

final notificationRepositoryProvider = Provider<NotificationRepository>((
  ref,
) {
  return NotificationRepositoryImpl(
    notificationApi: ref.watch(notificationApiProvider),
  );
});

/// API_SPEC §3.7 — `schedule`.
final weeklyAddressApiProvider = Provider<WeeklyAddressApi>((ref) {
  return WeeklyAddressApi(dio: ref.watch(apiClientProvider).dio);
});

final weeklyAddressRepositoryProvider = Provider<WeeklyAddressRepository>((
  ref,
) {
  return WeeklyAddressRepositoryImpl(
    weeklyAddressApi: ref.watch(weeklyAddressApiProvider),
  );
});

/// API_SPEC §3.8·§3.9 — `schedule`.
final changeRequestApiProvider = Provider<ChangeRequestApi>((ref) {
  return ChangeRequestApi(dio: ref.watch(apiClientProvider).dio);
});

final changeRequestRepositoryProvider = Provider<ChangeRequestRepository>((
  ref,
) {
  return ChangeRequestRepositoryImpl(
    changeRequestApi: ref.watch(changeRequestApiProvider),
  );
});

/// API_SPEC §3.2·§3.3·§3.4 — `child_link`.
final linkApiProvider = Provider<LinkApi>((ref) {
  return LinkApi(dio: ref.watch(apiClientProvider).dio);
});

final linkRepositoryProvider = Provider<LinkRepository>((ref) {
  return LinkRepositoryImpl(linkApi: ref.watch(linkApiProvider));
});

/// API_SPEC §3.14 — `settings`.
final notificationSettingsApiProvider = Provider<NotificationSettingsApi>((
  ref,
) {
  return NotificationSettingsApi(dio: ref.watch(apiClientProvider).dio);
});

final notificationSettingsRepositoryProvider =
    Provider<NotificationSettingsRepository>((ref) {
      return NotificationSettingsRepositoryImpl(
        notificationSettingsApi: ref.watch(notificationSettingsApiProvider),
      );
    });

/// API_SPEC §2.11 — `settings`. `TokenStorage` 와 달리 `AuthRepository`
/// 를 통해 서버와 통신하므로 여기서는 로컬 상태만 감싼다.
final deviceRegistrationStorageProvider = Provider<DeviceRegistrationStorage>(
  (ref) => DeviceRegistrationStorage(),
);
