import 'package:baraeda_core/baraeda_core.dart';

/// `TokenStorage` 의 시험용 대역 — `flutter_secure_storage` 의 플랫폼
/// 채널을 타지 않고 메모리에만 저장한다.
///
/// `flutter_test` 환경에는 시크릿 스토리지 플랫폼 채널이 물려 있지 않다 —
/// 실제 `TokenStorage`(기본 `FlutterSecureStorage`)를 그대로 쓰면
/// `authBootstrapProvider` 의 `readRefreshToken()` 호출이 응답 없는 채널
/// 요청에 걸려 `pumpAndSettle` 이 시간 초과한다. 생성자로 넘긴
/// `seedRefreshToken` 으로 "이미 로그인된 채 앱을 다시 켠 상태"(목표 표
/// 5항 자동 로그인)도 같은 대역으로 시험한다.
class FakeTokenStorage extends TokenStorage {
  new({String? seedRefreshToken, String? seedAccessToken})
    : _refreshToken = seedRefreshToken,
      _accessToken = seedAccessToken,
      super(
        accessTokenKey: 'test_access_token',
        refreshTokenKey: 'test_refresh_token',
      );

  String? _accessToken;
  String? _refreshToken;

  @override
  Future<String?> readAccessToken() async => _accessToken;

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
  }
}
