import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 명단 저장본 암호화 키의 보관소(`Ruling 872`) — 키는 기기 보안 저장소
/// (Keychain · EncryptedSharedPreferences)에만 두고 DB 에는 두지 않는다.
/// DB 파일만 새어 나가면 암호문뿐이다.
abstract interface class RosterKeyStore {
  Future<List<int>?> read();

  Future<void> write(List<int> key);

  Future<void> delete();
}

/// 기본 구현 — `flutter_secure_storage`. 키는 base64 문자열로 둔다.
class SecureRosterKeyStore implements RosterKeyStore {
  const new();

  static const _key = 'baraeda_manager_roster_key';
  static const _storage = FlutterSecureStorage();

  @override
  Future<List<int>?> read() async {
    try {
      final value = await _storage.read(key: _key);
      return value == null ? null : base64Decode(value);
    } on Object {
      // 읽지 못하면 "키 없음" — 저장본은 복호화할 수 없어 없는 것으로 취급된다.
      return null;
    }
  }

  @override
  Future<void> write(List<int> key) =>
      _storage.write(key: _key, value: base64Encode(key));

  @override
  Future<void> delete() async {
    try {
      await _storage.delete(key: _key);
    } on Object {
      // 지우지 못해도 로그아웃은 계속된다 — 명단 행은 이미 지워졌다.
    }
  }
}

/// 명단 저장본을 AES-GCM 256 으로 암호화한다(`Ruling 872` · NFR-08).
///
/// 저장 문자열은 `v1:` + base64(nonce 12바이트 · 암호문 · 인증 태그
/// 16바이트)이다. 키는 처음 쓸 때 무작위로 만들어 [RosterKeyStore] 에 둔다.
/// 복호화는 키가 없거나 인증 태그가 맞지 않거나(손상 · 변조) 옛 평문이면
/// `null` 이다.
class RosterCipher {
  new(this._keys);

  static const _prefix = 'v1:';
  static const _nonceLength = 12;
  static const _macLength = 16;

  final RosterKeyStore _keys;
  final AesGcm _algorithm = AesGcm.with256bits();

  /// 읽은 · 만든 키를 메모리에 묶어 둔다 — 키가 없는 채 동시에 두 번 저장해도
  /// 키를 둘 만들지 않는다. 만들다 실패하면 비운다(실패한 Future 가 남으면 앱을
  /// 다시 켜기 전까지 저장이 계속 실패한다).
  Future<SecretKey>? _cachedKey;

  /// 키를 만들거나 지우는 일을 한 줄로 세운다 — 로그아웃의 키 삭제와 겹친 저장이
  /// 삭제 뒤에 키를 되살리지 못하게 한다.
  Future<void> _keyQueue = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() body) {
    final run = _keyQueue.then((_) => body());
    _keyQueue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<SecretKey> _loadOrCreateKey() async {
    final stored = await _keys.read();
    if (stored != null && stored.length == 32) return SecretKey(stored);
    final key = await _algorithm.newSecretKey();
    await _keys.write(await key.extractBytes());
    return key;
  }

  Future<SecretKey> _key() async {
    final pending = _cachedKey ??= _serialized(_loadOrCreateKey);
    try {
      return await pending;
    } on Object {
      if (identical(_cachedKey, pending)) _cachedKey = null;
      rethrow;
    }
  }

  /// [plain] 을 암호화한 저장 문자열. 키가 없으면 새로 만든다.
  Future<String> encrypt(String plain) async {
    final key = await _key();
    final box = await _algorithm.encrypt(utf8.encode(plain), secretKey: key);
    return '$_prefix${base64Encode(box.concatenation())}';
  }

  /// [stored] 를 복호화한다. 읽을 수 없으면(키 없음 · 손상 · 평문) `null` — 키는 만들지 않는다.
  Future<String?> decrypt(String stored) async {
    if (!stored.startsWith(_prefix)) return null;
    try {
      final keyBytes = await _keys.read();
      if (keyBytes == null || keyBytes.length != 32) return null;
      final box = SecretBox.fromConcatenation(
        base64Decode(stored.substring(_prefix.length)),
        nonceLength: _nonceLength,
        macLength: _macLength,
      );
      final clear = await _algorithm.decrypt(
        box,
        secretKey: SecretKey(keyBytes),
      );
      return utf8.decode(clear);
    } on Object {
      return null;
    }
  }

  /// 키를 지운다 — 이후 남은 저장본은 어떤 경로로도 복호화되지 않는다.
  Future<void> deleteKey() async {
    _cachedKey = null;
    await _serialized(_keys.delete);
  }
}
