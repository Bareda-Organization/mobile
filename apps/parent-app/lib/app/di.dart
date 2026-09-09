import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/core/constants/api_constants.dart';

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
  return ApiClient(
    tokenStorage: ref.watch(tokenStorageProvider),
    baseUrl: ApiConstants.baseUrl,
  );
});
