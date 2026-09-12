import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// 단말 등록 로컬 상태 — API_SPEC §2.11.
///
/// 서버에 "현재 이 기기가 등록돼 있는가" 를 물어보는 조회 엔드포인트가
/// 없다(§2.11 은 등록·해지만 있고 목록 조회가 없음) — 그래서 마지막으로
/// 등록·해지에 성공한 토큰을 이 저장소에 남겨 화면의 on/off 표시 근거로
/// 쓴다. `TokenStorage`(baraeda_core)와 같은 "생성자로 저장 키를 받는
/// 구체 클래스" 패턴을 그대로 따른다 — 시험에서 하위 클래스로 대역을
/// 만들 수 있어야 하므로 메서드를 전부 override 가능하게 둔다.
///
/// `core/devices` 에 두는 이유 — 처음엔 `features/settings` 소유였으나,
/// `features/auth`(§2.11 pending 계정의 단말 등록 화면)도 이 저장소가
/// 필요해져 2개 feature 가 공유하게 됐다(`core/auth`·`core/students` 와
/// 같은 승격 기준, `CONVENTIONS_FLUTTER.md` §2 — feature 는 서로 직접
/// import 하지 않는다).
class DeviceRegistrationStorage {
  DeviceRegistrationStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _deviceIdKey = 'device_registration_device_id';
  static const _tokenKey = 'device_registration_token';

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

  /// 마지막으로 등록에 성공한 토큰. 등록된 적이 없거나 해지됐으면 `null`.
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  /// `POST /me/devices` 성공 직후 호출한다.
  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  /// `DELETE /me/devices/{token}` 성공 직후 호출한다.
  Future<void> clearToken() => _storage.delete(key: _tokenKey);
}
