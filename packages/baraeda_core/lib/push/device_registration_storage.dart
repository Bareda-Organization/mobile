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
  static const _accountKey = 'device_registration_account_id';

  /// 계정 구분이 없던 때의 키 — 이행에만 읽고, 계정별 키는 이 뒤에 `_<계정 id>` 를 붙인다.
  static const _legacyOptedOutKey = 'device_registration_opted_out';

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

  /// 이 기기에서 지금 쓰는 계정으로 정한다 — 로그인과 `/me` 가 부른다(`DeviceRegistrar`). 끔 기록이 계정 단위라서
  /// 어느 계정의 기록을 읽고 쓸지 여기서 정해진다(Ruling 885④).
  ///
  /// 계정 구분이 없던 옛 끔 기록(`_legacyOptedOutKey`)이 남아 있으면 이 기기에 처음 정해지는 계정에 붙이고
  /// 지운다 — 사용자가 끈 것을 다시 켜지 않는 쪽이다(누가 껐는지는 알 수 없어 처음 들어오는 계정이 받는다).
  Future<void> selectAccount(String accountId) async {
    await _storage.write(key: _accountKey, value: accountId);
    if (await _storage.read(key: _legacyOptedOutKey) == 'true') {
      await _storage.write(key: _optedOutKeyOf(accountId), value: 'true');
      await _storage.delete(key: _legacyOptedOutKey);
    }
  }

  /// 사용자가 이 기기에서 지금 계정의 알림을 직접 꺼 두었는가 — 켜져 있으면 로그인·앱 재실행이 자동으로 다시
  /// 등록하지 않는다. 계정이 정해진 적 없으면 `false`.
  Future<bool> readOptedOut() async {
    final key = await _activeOptedOutKey();
    return key != null && await _storage.read(key: key) == 'true';
  }

  /// 설정의 "이 기기에서 알림 받기" 스위치를 끌 때 `true`, 켤 때 `false` — 지금 계정에만 적용된다.
  /// 계정이 정해진 적 없으면(로그인한 적 없음) 아무것도 하지 않는다.
  Future<void> saveOptedOut({required bool optedOut}) async {
    final key = await _activeOptedOutKey();
    if (key == null) return;
    if (optedOut) {
      await _storage.write(key: key, value: 'true');
    } else {
      await _storage.delete(key: key);
    }
  }

  Future<String?> _activeOptedOutKey() async {
    final accountId = await _storage.read(key: _accountKey);
    return accountId == null ? null : _optedOutKeyOf(accountId);
  }

  static String _optedOutKeyOf(String accountId) =>
      '${_legacyOptedOutKey}_$accountId';
}
