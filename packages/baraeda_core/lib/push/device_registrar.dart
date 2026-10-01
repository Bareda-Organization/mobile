import 'package:baraeda_core/auth/models/device_registration.dart';
import 'package:baraeda_core/push/device_registration_storage.dart';
import 'package:baraeda_core/push/push_token_source.dart';
import 'package:flutter/foundation.dart';

/// 로그인 뒤 단말 토큰을 서버에 등록하고, 로그아웃 때 해지에 쓸 기기 식별자를
/// 내준다(NTF-12 · API_SPEC §2.7 · §2.11 · Ruling 510). `AuthApi` 가 로그인·
/// `/me`·로그아웃에서 부른다 — 화면은 이 흐름을 모른다.
class DeviceRegistrar {
  /// [platform] 은 서버 CHECK 값(`android` · `ios` · `web`)이다 — 기본은 실행
  /// 중인 플랫폼에서 정한다.
  DeviceRegistrar({
    required this._tokenSource,
    required this._storage,
    String? platform,
  }) : _platform = platform ?? _currentPlatform();

  final PushTokenSource _tokenSource;
  final DeviceRegistrationStorage _storage;
  final String _platform;

  /// 이번 실행에서 이미 등록한 토큰 — `/me` 가 호출될 때마다 같은 요청을
  /// 되풀이하지 않게 한다.
  String? _registeredToken;

  /// 토큰을 서버에 등록한다. 사용자가 기기 알림을 꺼 두었거나 공급자가 줄
  /// 토큰이 없으면 아무것도 하지 않는다.
  ///
  /// [force] 는 로그인 직후에 켠다 — 세션이 바뀌었으면 같은 토큰이라도 새
  /// 계정으로 다시 등록해야 한다(서버가 같은 토큰의 앞 계정 행을 해지한다,
  /// §2.11 "계정 전환"). 실패하면 예외를 그대로 던진다 — 삼킬지는 호출부가
  /// 정한다.
  Future<void> register(
    Future<void> Function(DeviceRegistrationRequest request) send, {
    bool force = false,
  }) async {
    if (await _storage.readOptedOut()) return;
    final token = await _tokenSource.currentToken();
    if (token == null || (!force && token == _registeredToken)) return;
    final deviceId = await _storage.readOrCreateDeviceId();
    await send(
      DeviceRegistrationRequest(
        token: token,
        platform: _platform,
        deviceId: deviceId,
      ),
    );
    _registeredToken = token;
    await _storage.saveToken(token);
  }

  /// 로그아웃 요청에 실을 기기 식별자 — 등록된 적이 없으면 `null`.
  Future<String?> deviceId() => _storage.readDeviceId();

  /// 로그아웃 직후 호출한다 — 서버가 토큰을 해지했으니 로컬 표시와 이번 실행의
  /// 등록 기록을 비운다.
  Future<void> forget() async {
    _registeredToken = null;
    await _storage.clearToken();
  }

  static String _currentPlatform() => switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    _ => 'web',
  };
}
