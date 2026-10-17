import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 기기 보안 저장소(Keychain · EncryptedSharedPreferences)의 칸 하나 — 키 하나를 읽고 쓰고 지운다.
///
/// 이 칸에 두는 값은 부가 기능이다. 그래서 기본은 저장소 오류를 삼킨다 — 읽기는 `null`("저장된 값 없음"),
/// 쓰기 · 지우기는 없던 일로 한다. 읽지 못한 것과 값이 없는 것을 구분해야 하면 `strict: true` 로 부른다.
/// 앱의 `*Store` / `*Storage` 는 이 칸 위의 얇은 접근자다(값 해석만 맡는다).
class SecureSlot {
  /// `key` 한 칸. `storage` 는 시험에서 가짜를 넣을 때만 준다.
  const new(this.key, {this._storage = const FlutterSecureStorage()});

  /// 저장 키.
  final String key;

  final FlutterSecureStorage _storage;

  /// 저장된 값. 없거나(그리고 [strict] 가 아닐 때) 읽지 못하면 `null`.
  Future<String?> read({bool strict = false}) async {
    try {
      return await _storage.read(key: key);
    } on Object {
      if (strict) rethrow;
      return null;
    }
  }

  /// 값을 저장한다. [strict] 가 아니면 저장 실패는 없던 일이다.
  Future<void> write(String value, {bool strict = false}) async {
    try {
      await _storage.write(key: key, value: value);
    } on Object {
      if (strict) rethrow;
    }
  }

  /// 값을 지운다. 지우지 못해도 호출한 쪽(로그아웃 등)은 계속된다.
  Future<void> delete() async {
    try {
      await _storage.delete(key: key);
    } on Object {
      // 지우지 못해도 호출한 쪽은 계속된다.
    }
  }
}
