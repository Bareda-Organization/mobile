import 'package:baraeda_core/baraeda_core.dart';
import 'package:manager_app/core/auth/last_session_store.dart';

/// [LastSessionStore] 의 메모리 대역 — 시험에는 `flutter_secure_storage` 플랫폼 채널이 없다.
class FakeLastSessionStore implements LastSessionStore {
  new([this.role]);

  AccountRole? role;

  @override
  Future<AccountRole?> readRole() async => role;

  @override
  Future<void> saveRole(AccountRole role) async => this.role = role;

  @override
  Future<void> clear() async => role = null;
}
