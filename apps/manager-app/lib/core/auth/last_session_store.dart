import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 마지막으로 `/me` 가 확인해 준 **활성 계정의 역할**(`driver` · `escort`) 하나를 이 기기에 남겨 둔다(R52 H2).
///
/// 통신이 끊긴 채 앱을 새로 켜면 `/me` 를 못 받아 역할을 알 수 없고, 역할이 없으면 홈 · 저장 명단 · 비상 신고 ·
/// 학원 전화가 모두 닿지 않는다(NFR-01 · M-06). 이 값이 있고 refresh 토큰이 남아 있으면 `/me` 가 네트워크 실패여도
/// 이 역할로 들어가고, 연결이 돌아오면 `/me` 로 다시 확인한다. 이름 · 전화번호 같은 개인정보는 저장하지 않는다
/// (개인정보 등급 L2 이상 금지) — 역할 판정에 필요한 최소값뿐이다. 로그아웃 · 세션 만료 · 인증 거절 때 지운다.
abstract interface class LastSessionStore {
  Future<AccountRole?> readRole();

  Future<void> saveRole(AccountRole role);

  Future<void> clear();
}

/// 기본 구현 — `flutter_secure_storage`(Keychain · EncryptedSharedPreferences).
class SecureLastSessionStore implements LastSessionStore {
  const new();

  static const _key = 'baraeda_manager_last_role';
  static const _storage = FlutterSecureStorage();

  @override
  Future<AccountRole?> readRole() async {
    try {
      final value = await _storage.read(key: _key);
      return value == null ? null : AccountRole.fromWireValueOrNull(value);
    } on Object {
      // 읽지 못하면 "저장된 역할 없음" — 앱은 지금처럼 다시 시도 안내를 보인다.
      return null;
    }
  }

  @override
  Future<void> saveRole(AccountRole role) async {
    try {
      await _storage.write(key: _key, value: role.wireValue);
    } on Object {
      // 저장 실패는 로그인을 막지 않는다 — 부가 기능이다.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } on Object {
      // 지우지 못해도 로그아웃은 계속된다 — 토큰이 없으면 이 값은 쓰이지 않는다.
    }
  }
}

/// 시험은 이 provider 를 메모리 대역으로 바꾼다(플랫폼 채널이 없다).
final Provider<LastSessionStore> lastSessionStoreProvider =
    Provider<LastSessionStore>((ref) => const SecureLastSessionStore());
