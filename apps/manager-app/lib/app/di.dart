import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/constants/api_constants.dart';
import 'package:manager_app/core/constants/navigation_constants.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/wakelock/wakelock_port.dart';
import 'package:manager_app/features/auth/data/auth_repository_impl.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/delay/data/delay_api.dart';
import 'package:manager_app/features/delay/data/delay_repository_impl.dart';
import 'package:manager_app/features/delay/domain/delay_repository.dart';
import 'package:manager_app/features/drive_mode/data/drive_mode_api.dart';
import 'package:manager_app/features/drive_mode/data/drive_mode_repository_impl.dart';
import 'package:manager_app/features/drive_mode/domain/drive_mode_repository.dart';
import 'package:manager_app/features/emergency/data/emergency_api.dart';
import 'package:manager_app/features/emergency/data/emergency_repository_impl.dart';
import 'package:manager_app/features/emergency/domain/emergency_repository.dart';
import 'package:manager_app/features/home/data/manager_run_api.dart';
import 'package:manager_app/features/home/data/manager_run_repository_impl.dart';
import 'package:manager_app/features/home/domain/manager_run_repository.dart';
import 'package:manager_app/features/navigation/data/kakao_navi_launcher.dart';
import 'package:manager_app/features/navigation/data/navigation_api.dart';
import 'package:manager_app/features/navigation/data/navigation_repository_impl.dart';
import 'package:manager_app/features/navigation/domain/navigation_repository.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_repository_impl.dart';
import 'package:manager_app/features/offline_queue/domain/offline_queue_repository.dart';
import 'package:manager_app/features/position/data/position_api.dart';
import 'package:manager_app/features/position/data/position_repository_impl.dart';
import 'package:manager_app/features/position/domain/position_repository.dart';
import 'package:manager_app/features/roster/data/drift_roster_cache.dart';
import 'package:manager_app/features/roster/data/guardian_phone_repository_impl.dart';
import 'package:manager_app/features/roster/data/roster_api.dart';
import 'package:manager_app/features/roster/data/roster_cipher.dart';
import 'package:manager_app/features/roster/data/roster_repository_impl.dart';
import 'package:manager_app/features/roster/domain/guardian_phone_repository.dart';
import 'package:manager_app/features/roster/domain/roster_cache.dart';
import 'package:manager_app/features/roster/domain/roster_repository.dart';
import 'package:manager_app/features/route_map/data/route_api.dart';
import 'package:manager_app/features/route_map/data/route_repository_impl.dart';
import 'package:manager_app/features/route_map/domain/route_repository.dart';
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
    deviceRegistrar: ref.watch(deviceRegistrarProvider),
  );
});

/// 단말 등록 로컬 상태(NTF-12) — 기기 식별자와 마지막 등록 토큰.
final deviceRegistrationStorageProvider = Provider<DeviceRegistrationStorage>(
  (ref) => DeviceRegistrationStorage(),
);

/// 푸시 토큰 공급자(NTF-12 · Ruling 510) — Firebase 를 붙이기 전에는 기기별
/// 자리표시 토큰이다. Firebase 를 붙일 때 이 provider 한 곳만 바꾼다
/// (`docs/backend/infra/DEPLOYMENT.md` "외부 연동 준비물").
final pushTokenSourceProvider = Provider<PushTokenSource>(
  (ref) => PlaceholderPushTokenSource(
    ref.watch(deviceRegistrationStorageProvider),
  ),
);

/// 로그인 뒤 단말 등록 · 로그아웃 해지 — `AuthApi` 가 부른다. 매니저는 알림
/// on/off 권한이 없어(FEATURE_SPEC §4.15) 끄기 스위치가 없다.
final deviceRegistrarProvider = Provider<DeviceRegistrar>(
  (ref) => DeviceRegistrar(
    tokenSource: ref.watch(pushTokenSourceProvider),
    storage: ref.watch(deviceRegistrationStorageProvider),
  ),
);

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
  return DriveModeRepositoryImpl(
    api: ref.watch(driveModeApiProvider),
    offlineQueue: ref.watch(offlineQueueRepositoryProvider),
  );
});

/// API_SPEC §4.2·§4.6·§4.7·§4.8 — 명단 조회 + 개인별 승하차 처리.
final rosterApiProvider = Provider<RosterApi>((ref) {
  return RosterApi(dio: ref.watch(apiClientProvider).dio);
});

/// 마지막으로 받은 명단의 로컬 저장소(M-M3) — 오프라인 대기열과 같은 기기 DB 를 쓴다.
final rosterCacheProvider = Provider<RosterCache>((ref) {
  return DriftRosterCache(
    database: ref.watch(offlineQueueDatabaseProvider),
    cipher: ref.watch(rosterCipherProvider),
  );
});

/// 명단 저장본 암호화(`Ruling 872`) — 키는 기기 보안 저장소에 둔다. 시험은
/// [rosterKeyStoreProvider] 를 메모리 대역으로 바꾼다(플랫폼 채널이 없다).
final rosterKeyStoreProvider = Provider<RosterKeyStore>(
  (ref) => const SecureRosterKeyStore(),
);

final rosterCipherProvider = Provider<RosterCipher>(
  (ref) => RosterCipher(ref.watch(rosterKeyStoreProvider)),
);

final rosterRepositoryProvider = Provider<RosterRepository>((ref) {
  return RosterRepositoryImpl(
    api: ref.watch(rosterApiProvider),
    offlineQueue: ref.watch(offlineQueueRepositoryProvider),
    cache: ref.watch(rosterCacheProvider),
    // 로그아웃 뒤에 늦게 도착한 응답을 기기에 남기지 않는다(M-2).
    isSignedIn: () => ref.read(currentUserRoleProvider) != null,
  );
});

/// API_SPEC §4.2.1 — 보호자 전화 원번호(명단 [전화] 버튼, Ruling 482).
final guardianPhoneRepositoryProvider = Provider<GuardianPhoneRepository>((
  ref,
) {
  return GuardianPhoneRepositoryImpl(api: ref.watch(rosterApiProvider));
});

/// API_SPEC §4.3 — 실시간 노선 조회(RouteMapScreen, 기사·동승자 둘 다).
final routeApiProvider = Provider<RouteApi>((ref) {
  return RouteApi(dio: ref.watch(apiClientProvider).dio);
});

final routeRepositoryProvider = Provider<RouteRepository>((ref) {
  return RouteRepositoryImpl(api: ref.watch(routeApiProvider));
});

/// API_SPEC §4.16 — 외부 내비 좌표열(기사 전용 화면이 쓴다).
final navigationApiProvider = Provider<NavigationApi>((ref) {
  return NavigationApi(dio: ref.watch(apiClientProvider).dio);
});

final navigationRepositoryProvider = Provider<NavigationRepository>((ref) {
  return NavigationRepositoryImpl(api: ref.watch(navigationApiProvider));
});

/// 카카오내비 앱 키 — 빈 값이면 외부 내비 버튼이 없다. 시험이 바꿔 끼운다.
final kakaoNaviAppKeyProvider = Provider<String>(
  (ref) => NavigationConstants.kakaoAppKey,
);

/// 카카오내비를 여는 경계(공식 SDK) — 시험이 가짜로 바꿔 끼워 실제 앱을 열지 않는다.
final kakaoNaviLauncherProvider = Provider<KakaoNaviLauncher>(
  (ref) => SdkKakaoNaviLauncher(appKey: ref.watch(kakaoNaviAppKeyProvider)),
);

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

/// API_SPEC §1.7 오프라인 큐(M-06) — drift 로컬 DB 하나를 앱 전역에서
/// 공유한다(승하차 처리·비상 발신 재생이 같은 큐를 쓴다).
final offlineQueueDatabaseProvider = Provider<OfflineQueueDatabase>((ref) {
  final database = OfflineQueueDatabase();
  ref.onDispose(database.close);
  return database;
});

final offlineQueueRepositoryProvider = Provider<OfflineQueueRepository>((ref) {
  return OfflineQueueRepositoryImpl(
    database: ref.watch(offlineQueueDatabaseProvider),
    dio: ref.watch(apiClientProvider).dio,
    clock: ref.watch(clockProvider),
  );
});

/// LOC-01 — 좌표 획득 소스. `geolocator` 로 실제 GPS 좌표를 낸다
/// (`core/location/position_source.dart` 문서 주석 참고). 시험은 이 provider 를
/// 가짜 [PositionSource] 로 덮는다.
final positionSourceProvider = Provider<PositionSource>((ref) {
  final source = GeolocatorPositionSource();
  ref.onDispose(source.dispose);
  return source;
});

/// F2 — 운행 화면이 켜져 있는 동안 화면 꺼짐을 막는다(백그라운드 GPS
/// 송신이 범위 밖이라 화면이 켜진 상태가 지금 송신을 지키는 유일한
/// 수단, M-B 2항). 시험은 이 provider 를 가짜 [WakelockPort] 로 덮는다.
final wakelockPortProvider = Provider<WakelockPort>(
  (ref) => WakelockPlusPort(),
);

/// API_SPEC §4.12 — 위치 업로드(기사 전용). §1.7 대상이 아니라 오프라인
/// 큐를 거치지 않는다(재시도가 오래된 좌표를 나중에 보내면 오히려
/// 근접 판정을 그르친다 — 실패하면 다음 주기 전송이 대신한다).
final positionApiProvider = Provider<PositionApi>((ref) {
  return PositionApi(dio: ref.watch(apiClientProvider).dio);
});

final positionRepositoryProvider = Provider<PositionRepository>((ref) {
  return PositionRepositoryImpl(api: ref.watch(positionApiProvider));
});

/// API_SPEC §4.14·§4.15 — 비상 발신·취소·목록. 역할 제한 없음(기사·동승자
/// 둘 다 호출 가능).
final emergencyApiProvider = Provider<EmergencyApi>((ref) {
  return EmergencyApi(dio: ref.watch(apiClientProvider).dio);
});

final emergencyRepositoryProvider = Provider<EmergencyRepository>((ref) {
  return EmergencyRepositoryImpl(
    api: ref.watch(emergencyApiProvider),
    offlineQueue: ref.watch(offlineQueueRepositoryProvider),
  );
});

/// API_SPEC §3.12·§3.13 — 알림 목록·읽음 처리. `NotificationApi` 는 `baraeda_core` 소유라
/// 학부모·학생 앱과 같은 것을 쓴다.
final notificationApiProvider = Provider<NotificationApi>((ref) {
  return NotificationApi(dio: ref.watch(apiClientProvider).dio);
});

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepositoryImpl(
    notificationApi: ref.watch(notificationApiProvider),
  );
});
