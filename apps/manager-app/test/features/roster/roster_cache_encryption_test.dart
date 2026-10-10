import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:manager_app/features/roster/data/drift_roster_cache.dart';
import 'package:manager_app/features/roster/data/roster_cipher.dart';

import '../../support/fake_roster_key_store.dart';

/// `Ruling 872` · NFR-08 — 기기에 저장한 명단은 학생 이름 · 특이사항(L3)을
/// 담으므로 DB 의 `payload` 는 암호문이어야 하고, 키는 보안 저장소에만 있으며,
/// 로그아웃에 저장본과 키가 함께 사라지고, 읽을 수 없는 저장본은 없는 것으로
/// 지워진다.
const _json = <String, dynamic>{
  'run_id': 'run-1',
  'bus_no': '3호차',
  'stops': [
    {
      'stop_id': 's1',
      'students': [
        {'name': '김바래', 'note': '견과류 알레르기', 'guardian_phone': '010-****-1234'},
      ],
    },
  ],
};

void main() {
  late OfflineQueueDatabase database;
  late FakeRosterKeyStore keys;
  late DriftRosterCache cache;

  setUp(() {
    database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
    keys = FakeRosterKeyStore();
    cache = DriftRosterCache(database: database, cipher: RosterCipher(keys));
  });
  tearDown(() => database.close());

  Future<List<CachedRoster>> rows() =>
      database.select(database.cachedRosters).get();

  test('저장한 payload 원문에 학생 이름 · 특이사항 · 전화번호가 없다', () async {
    await cache.save('run-1', _json);

    final stored = (await rows()).single.payload;
    for (final secret in [
      '김바래',
      '견과류 알레르기',
      '010-****-1234',
      'guardian_phone',
    ]) {
      expect(stored, isNot(contains(secret)), reason: secret);
    }
  });

  test('저장한 명단을 그대로 복호화해 읽는다', () async {
    await cache.save('run-1', _json);

    final read = await cache.read('run-1');

    expect(read!.json, _json);
  });

  test('같은 명단을 두 번 저장해도 암호문이 다르고 키는 한 번만 만든다', () async {
    await cache.save('run-1', _json);
    final first = (await rows()).single.payload;
    await cache.save('run-1', _json);
    final second = (await rows()).single.payload;

    expect(second, isNot(first), reason: '저장마다 nonce 가 새로 정해진다');
    expect(keys.writes, 1);
    expect(keys.key, hasLength(32), reason: 'AES-256 키');
  });

  test('로그아웃(clear) 뒤에는 저장본도 키도 없다', () async {
    await cache.save('run-1', _json);
    await cache.save('run-2', _json);

    await cache.clear();

    expect(await rows(), isEmpty);
    expect(keys.key, isNull);
  });

  test('clear 뒤 새로 저장하면 새 키로 암호화한다', () async {
    await cache.save('run-1', _json);
    final oldKey = List<int>.of(keys.key!);
    await cache.clear();

    await cache.save('run-1', _json);

    expect(keys.key, isNot(oldKey));
    expect((await cache.read('run-1'))!.json, _json);
  });

  test('손상된 저장본은 없는 것으로 읽히고 그 행은 지워진다', () async {
    await cache.save('run-1', _json);
    final stored = (await rows()).single.payload;
    // 마지막 글자를 바꿔 인증 태그가 맞지 않게 한다.
    final tampered =
        stored.substring(0, stored.length - 4) +
        (stored.endsWith('AAAA') ? 'BBBB' : 'AAAA');
    await database
        .update(database.cachedRosters)
        .write(CachedRostersCompanion(payload: Value(tampered)));

    expect(await cache.read('run-1'), isNull);
    expect(await rows(), isEmpty);
  });

  test('키가 없으면 저장본은 없는 것으로 읽히고 그 행은 지워진다', () async {
    await cache.save('run-1', _json);
    keys.key = null;

    expect(await cache.read('run-1'), isNull);
    expect(await rows(), isEmpty);
  });

  test('암호화 이전의 평문 저장본도 없는 것으로 지운다', () async {
    await database
        .into(database.cachedRosters)
        .insert(
          CachedRostersCompanion.insert(
            runId: 'run-1',
            payload: '{"run_id":"run-1"}',
            savedAt: DateTime(2026, 10, 10),
          ),
        );

    expect(await cache.read('run-1'), isNull);
    expect(await rows(), isEmpty);
  });

  test('읽기만 해서는 키를 만들지 않는다', () async {
    expect(await cache.read('run-1'), isNull);

    expect(keys.writes, 0);
  });
}
