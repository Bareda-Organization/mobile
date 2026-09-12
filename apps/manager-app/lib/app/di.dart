import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/core/constants/api_constants.dart';
import 'package:manager_app/features/auth/data/auth_repository_impl.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/delay/data/delay_api.dart';
import 'package:manager_app/features/delay/data/delay_repository_impl.dart';
import 'package:manager_app/features/delay/domain/delay_repository.dart';
import 'package:manager_app/features/drive_mode/data/drive_mode_api.dart';
import 'package:manager_app/features/drive_mode/data/drive_mode_repository_impl.dart';
import 'package:manager_app/features/drive_mode/domain/drive_mode_repository.dart';
import 'package:manager_app/features/home/data/manager_run_api.dart';
import 'package:manager_app/features/home/data/manager_run_repository_impl.dart';
import 'package:manager_app/features/home/domain/manager_run_repository.dart';
import 'package:manager_app/features/roster/data/roster_api.dart';
import 'package:manager_app/features/roster/data/roster_repository_impl.dart';
import 'package:manager_app/features/roster/domain/roster_repository.dart';
import 'package:manager_app/features/run_end/data/reports_api.dart';
import 'package:manager_app/features/run_end/data/reports_repository_impl.dart';
import 'package:manager_app/features/run_end/domain/reports_repository.dart';

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

/// 위젯 안에서 `DateTime.now()` 를 직접 부르지 않기 위한 주입 지점
/// (CONVENTIONS_FLUTTER.md §9, 이월 11 · Ruling 266). 운영 기본값은
/// [SystemClock] 이고, 테스트는 이 provider 를 override 해 시각을 고정한다 —
/// 값을 여기서 얼리지 않는다(운행 시작 창 판정은 실제 "지금" 이 필요하다).
final clockProvider = Provider<Clock>((ref) => const SystemClock());

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

/// API_SPEC §4.1 — ManagerHome 이 오늘의 회차 목록을 읽는 통로.
final managerRunApiProvider = Provider<ManagerRunApi>((ref) {
  return ManagerRunApi(dio: ref.watch(apiClientProvider).dio);
});

final managerRunRepositoryProvider = Provider<ManagerRunRepository>((ref) {
  return ManagerRunRepositoryImpl(api: ref.watch(managerRunApiProvider));
});

/// API_SPEC §4.4·§4.5 — 운행 시작·승하차지 도착(기사 전용).
final driveModeApiProvider = Provider<DriveModeApi>((ref) {
  return DriveModeApi(dio: ref.watch(apiClientProvider).dio);
});

final driveModeRepositoryProvider = Provider<DriveModeRepository>((ref) {
  return DriveModeRepositoryImpl(api: ref.watch(driveModeApiProvider));
});

/// API_SPEC §4.2·§4.6·§4.7·§4.8 — 명단 조회 + 개인별 승하차 처리.
final rosterApiProvider = Provider<RosterApi>((ref) {
  return RosterApi(dio: ref.watch(apiClientProvider).dio);
});

final rosterRepositoryProvider = Provider<RosterRepository>((ref) {
  return RosterRepositoryImpl(api: ref.watch(rosterApiProvider));
});

/// API_SPEC §4.9 — 지연 알림(동승자 전용).
final delayApiProvider = Provider<DelayApi>((ref) {
  return DelayApi(dio: ref.watch(apiClientProvider).dio);
});

final delayRepositoryProvider = Provider<DelayRepository>((ref) {
  return DelayRepositoryImpl(api: ref.watch(delayApiProvider));
});

/// API_SPEC §4.13 — 현장 상황 보고(RunEndScreen 이 종료 리포트로 쓴다).
final reportsApiProvider = Provider<ReportsApi>((ref) {
  return ReportsApi(dio: ref.watch(apiClientProvider).dio);
});

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepositoryImpl(api: ref.watch(reportsApiProvider));
});
