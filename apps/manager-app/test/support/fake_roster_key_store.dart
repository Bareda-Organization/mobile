import 'package:manager_app/features/roster/data/roster_cipher.dart';

/// [RosterKeyStore] 의 메모리 대역 — 시험에는 `flutter_secure_storage` 플랫폼 채널이 없다.
class FakeRosterKeyStore implements RosterKeyStore {
  List<int>? key;

  /// 키를 쓴 횟수 — 처음 한 번만 만들고 다시 쓰지 않는지 본다.
  int writes = 0;

  @override
  Future<List<int>?> read() async => key;

  @override
  Future<void> write(List<int> key) async {
    writes++;
    this.key = List<int>.of(key);
  }

  @override
  Future<void> delete() async => key = null;
}
