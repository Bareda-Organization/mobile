import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/core/constants/api_constants.dart';
import 'package:manager_app/features/auth/data/auth_repository_impl.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';

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
