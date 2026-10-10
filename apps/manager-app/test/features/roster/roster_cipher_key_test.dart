import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/roster/data/roster_cipher.dart';

import '../../support/fake_roster_key_store.dart';

/// [failures] 번 쓰기에 실패한 뒤 정상으로 돌아오는 키 보관소.
class _FlakyKeyStore extends FakeRosterKeyStore {
  new(this.failures);

  int failures;

  @override
  Future<void> write(List<int> key) async {
    if (failures > 0) {
      failures--;
      throw StateError('보안 저장소 쓰기 실패');
    }
    await super.write(key);
  }
}

/// 쓰기가 [release] 될 때까지 멈춰 있는 키 보관소 — 키를 만드는 도중에 로그아웃이 겹친 상황.
class _SlowWriteKeyStore extends FakeRosterKeyStore {
  final release = Completer<void>();

  @override
  Future<void> write(List<int> key) async {
    await release.future;
    await super.write(key);
  }
}

/// 키 보관소 쓰기 실패 뒤에도 다음 저장이 되살아나야 하고, 로그아웃(키 삭제)과 겹친 저장이 삭제 뒤에 키를
/// 되살리지 못해야 한다(`Ruling 872`).
void main() {
  test('키 쓰기가 한 번 실패해도 다음 저장은 키를 다시 만들어 성공한다', () async {
    final keys = _FlakyKeyStore(1);
    final cipher = RosterCipher(keys);

    await expectLater(cipher.encrypt('명단'), throwsStateError);
    final stored = await cipher.encrypt('명단');

    expect(await cipher.decrypt(stored), '명단');
  });

  test('키를 만드는 도중 로그아웃(키 삭제)이 겹쳐도 삭제 뒤에 키가 남지 않는다', () async {
    final keys = _SlowWriteKeyStore();
    final cipher = RosterCipher(keys);

    final saving = cipher.encrypt('명단');
    await Future<void>.delayed(Duration.zero);
    final deleting = cipher.deleteKey();
    keys.release.complete();
    await saving;
    await deleting;

    expect(keys.key, isNull);
  });
}
