// 필드는 비공개로 두고 생성자 파라미터만 공개 이름을 쓰므로(아래 클래스 문서 참고)
// initializing formal 대신 초기화 리스트로 대입한다 — 그 대입 2줄에 한해 억제.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// access·refresh 토큰을 담는 곳. 평문 저장 금지(CONVENTIONS_FLUTTER.md §1) —
/// `flutter_secure_storage` 뒤에만 둔다. 화면·provider 는 이 클래스를 거쳐서만
/// 토큰을 읽고 쓴다.
///
/// 저장 키는 앱마다 생성자로 주입한다 — 이 패키지는 `parent_app` ·
/// `manager_app` 양쪽이 함께 쓰므로, 키를 이 파일에 고정하면 두 앱이 같은
/// 이름으로 저장하게 된다.
class TokenStorage {
  /// [accessTokenKey]·[refreshTokenKey] 는 앱이 넘기는 저장 키다.
  new({
    required String accessTokenKey,
    required String refreshTokenKey,
    FlutterSecureStorage? storage,
  }) : _accessTokenKey = accessTokenKey,
       _refreshTokenKey = refreshTokenKey,
       _storage = storage ?? const FlutterSecureStorage();

  final String _accessTokenKey;
  final String _refreshTokenKey;
  final FlutterSecureStorage _storage;

  /// 저장된 access 토큰. 없으면 `null`.
  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  /// 저장된 refresh 토큰. 없으면 `null`.
  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  /// 로그인·재발급으로 얻은 토큰 한 쌍을 저장한다.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  /// [clear] 가 불린 횟수 — 재발급처럼 응답을 기다리는 동안 로그아웃이 끼어들었는지
  /// 알아내는 표식이다. 시작 때 읽어 둔 값이 저장 직전에 달라졌으면 그 사이 세션이 끝난 것이다.
  int get clearCount => _clearCount;
  int _clearCount = 0;

  /// 로그아웃·재발급 실패 시 두 토큰을 모두 지운다.
  Future<void> clear() async {
    _clearCount += 1;
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}
