import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 마지막으로 로그인에 성공한 학원의 대표 연락처를 이 기기에 남겨 둔다(`Ruling 825`).
///
/// 계정이 잠기면 로그인 자체가 실패해 서버에서 학원 번호를 받을 길이 없다 — 차단 화면이 보일 번호는 앞서 성공한
/// 로그인 응답 · `/me` 의 `academy.contact` 를 여기에 저장해 둔 값뿐이다. 로그아웃해도 지우지 않는다(차단 화면은
/// 로그아웃한 사람이 본다). 학원의 대표 번호라 개인정보가 아니다.
abstract interface class AcademyContactStore {
  Future<String?> read();

  /// [contact] 가 `null` 이거나 비어 있으면 기존 값을 그대로 둔다 — 학원이 번호를 지웠다고 해서 이 기기가 알던
  /// 번호까지 잃을 이유는 없다.
  Future<void> save(String? contact);
}

/// 기본 구현 — `flutter_secure_storage`(Keychain · EncryptedSharedPreferences).
class SecureAcademyContactStore implements AcademyContactStore {
  const new();

  static const _key = 'baraeda_manager_academy_contact';
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } on Object {
      // 읽지 못하면 "저장된 번호 없음" 으로 본다 — 차단 화면이 안내 문장으로 대신한다.
      return null;
    }
  }

  @override
  Future<void> save(String? contact) async {
    final value = contact?.trim();
    if (value == null || value.isEmpty) return;
    try {
      await _storage.write(key: _key, value: value);
    } on Object {
      // 저장 실패는 로그인을 막지 않는다 — 부가 기능이다.
    }
  }
}

/// 시험은 이 provider 를 메모리 대역으로 바꾼다(플랫폼 채널이 없다).
final Provider<AcademyContactStore> academyContactStoreProvider =
    Provider<AcademyContactStore>((ref) => const SecureAcademyContactStore());

/// 차단 화면이 읽는 저장된 번호 — 없으면 `null`.
final FutureProvider<String?> savedAcademyContactProvider =
    FutureProvider.autoDispose<String?>(
      (ref) => ref.watch(academyContactStoreProvider).read(),
    );
