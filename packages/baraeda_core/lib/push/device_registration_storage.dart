import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// 단말 등록 로컬 상태 — API_SPEC §2.11.
///
/// 서버에 "현재 이 기기가 등록돼 있는가" 를 물어보는 조회 엔드포인트가
/// 없다(§2.11 은 등록·해지만 있고 목록 조회가 없음) — 그래서 마지막으로
/// 등록·해지에 성공한 토큰을 이 저장소에 남겨 화면의 on/off 표시 근거로
/// 쓴다. `TokenStorage` 와 같은 "구체 클래스" 패턴이라 시험에서 하위
/// 클래스로 대역을 만들 수 있게 메서드를 전부 override 가능하게 둔다.
///
/// 원래 `parent-app` 소유였으나, 로그인 뒤 자동 등록(`DeviceRegistrar` ·
/// Ruling 510)을 두 앱이 함께 하게 되면서 공용 패키지로 올렸다. 저장 키는
/// 그대로라 이미 설치된 앱의 값이 이어진다.
class DeviceRegistrationStorage {
  /// [storage] 는 시험에서 가짜를 넣을 때만 준다.
  new({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _deviceIdKey = 'device_registration_device_id';
  static const _tokenKey = 'device_registration_token';
  static const _optedOutKey = 'device_registration_opted_out';

  final FlutterSecureStorage _storage;

  /// 기기 식별자 — 한 번 생성하면 앱 재설치 전까지 고정한다(같은 기기의
  /// 토큰 갱신을 서버가 같은 행으로 인식하게 하는 값, §2.11 `device_id`).
  Future<String> readOrCreateDeviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null) return existing;
    final generated = const Uuid().v4();
    await _storage.write(key: _deviceIdKey, value: generated);
    return generated;
  }

  /// 만들지 않고 읽는다 — 로그아웃이 등록된 적 없는 기기의 식별자를 새로
  /// 만들어 보내지 않게 한다. 없으면 `null`.
  Future<String?> readDeviceId() => _storage.read(key: _deviceIdKey);

  /// 마지막으로 등록에 성공한 토큰. 등록된 적이 없거나 해지됐으면 `null`.
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  /// `POST /me/devices` 성공 직후 호출한다.
  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  /// `DELETE /me/devices/{token}` 또는 로그아웃 직후 호출한다.
  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  /// 사용자가 이 기기의 알림을 직접 꺼 두었는가 — 켜져 있으면 로그인·앱
  /// 재실행이 자동으로 다시 등록하지 않는다.
  Future<bool> readOptedOut() async =>
      await _storage.read(key: _optedOutKey) == 'true';

  /// 설정의 "이 기기에서 알림 받기" 스위치를 끌 때 `true`, 켤 때 `false`.
  Future<void> saveOptedOut({required bool optedOut}) => optedOut
      ? _storage.write(key: _optedOutKey, value: 'true')
      : _storage.delete(key: _optedOutKey);
}
