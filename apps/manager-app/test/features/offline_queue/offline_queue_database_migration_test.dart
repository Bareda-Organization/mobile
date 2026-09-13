import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  // FE-R2 목표 11 — v2 의 `client_key` 컬럼은 쓰기만 되고 어디서도 읽히지
  // 않아 컬럼째 제거했다(실제 멱등성은 payload 안 값이 지킨다). 이미 v2로
  // 기동한 기기가 있을 수 있으므로, 그 기기의 로컬 DB 를 흉내 내 마이그레이션이
  // 실제로 컬럼을 지우고 기존 행을 보존하는지 확인한다.
  test('v2(client_key 포함) DB 가 v3 로 열리면 컬럼이 제거되고 기존 행은 남는다', () async {
    final dir = Directory.systemTemp.createTempSync('oq_migration_test');
    final path = '${dir.path}/oq.sqlite';

    // v2 스키마를 손으로 만든다 — 실기기의 v2 로컬 DB 를 흉내 낸다.
    final raw = sqlite3.sqlite3.open(path);
    raw.execute('''
      CREATE TABLE pending_requests (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        client_key TEXT NOT NULL,
        endpoint TEXT NOT NULL,
        method TEXT NOT NULL DEFAULT 'PATCH',
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (unixepoch())
      );
    ''');
    raw.execute(
      "INSERT INTO pending_requests (client_key, endpoint, payload) VALUES ('K1', '/x', '{}')",
    );
    raw.execute('PRAGMA user_version = 2');
    raw.dispose();

    final db = OfflineQueueDatabase.forTesting(NativeDatabase(File(path)));
    // 아무 쿼리나 던지면 drift 가 open 시점에 마이그레이션을 실행한다.
    final rows = await db.select(db.pendingRequests).get();
    expect(rows, hasLength(1));
    expect(rows.single.endpoint, '/x');
    await db.close();

    // client_key 컬럼이 실제로 사라졌는지 raw pragma 로 직접 확인한다.
    final raw2 = sqlite3.sqlite3.open(path);
    final columns = raw2
        .select('PRAGMA table_info(pending_requests)')
        .map((r) => r['name'] as String)
        .toList();
    raw2.dispose();
    expect(columns, isNot(contains('client_key')));
  });
}
