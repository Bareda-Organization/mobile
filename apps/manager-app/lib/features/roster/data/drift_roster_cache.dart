import 'dart:convert';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:drift/drift.dart' show ComparableExpr;
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:manager_app/features/roster/data/roster_cipher.dart';
import 'package:manager_app/features/roster/domain/roster_cache.dart';

/// [RosterCache] 구현 — 오프라인 대기열과 같은 기기 DB(drift)의 `cached_rosters` 표를 쓴다.
///
/// 명단에는 학생 이름 · 특이사항이 있어 `payload` 는 암호문이다(`Ruling 872` · AES-GCM 256, 키는 기기 보안
/// 저장소). 읽을 때 복호화에 실패하거나 키가 없으면 그 행을 지우고 "저장본 없음" 으로 돌려준다.
class DriftRosterCache implements RosterCache {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을 쓴다.
  const new({
    required OfflineQueueDatabase database,
    required RosterCipher cipher,
    Clock clock = const SystemClock(),
  })
    // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을 쓴다.
    // ignore: prefer_initializing_formals
    : _database = database,
       // 위와 같은 이유.
       // ignore: prefer_initializing_formals
       _cipher = cipher,
       // 위와 같은 이유.
       // ignore: prefer_initializing_formals
       _clock = clock;

  /// 이 기간이 지난 저장본은 새로 저장할 때 치운다 — 지난 운행의 명단을 기기에 계속 쌓아 두지 않는다.
  static const keepFor = Duration(days: 2);

  final OfflineQueueDatabase _database;
  final RosterCipher _cipher;
  final Clock _clock;

  @override
  Future<void> save(String runId, Map<String, dynamic> json) async {
    final now = _clock.now();
    final payload = await _cipher.encrypt(jsonEncode(json));
    await _database
        .into(_database.cachedRosters)
        .insertOnConflictUpdate(
          CachedRostersCompanion.insert(
            runId: runId,
            payload: payload,
            savedAt: now,
          ),
        );
    await (_database.delete(
      _database.cachedRosters,
    )..where((t) => t.savedAt.isSmallerThanValue(now.subtract(keepFor)))).go();
  }

  @override
  Future<({Map<String, dynamic> json, DateTime savedAt})?> read(
    String runId,
  ) async {
    final row = await (_database.select(
      _database.cachedRosters,
    )..where((t) => t.runId.equals(runId))).getSingleOrNull();
    if (row == null) return null;
    final clear = await _cipher.decrypt(row.payload);
    final decoded = clear == null ? null : _tryDecode(clear);
    if (decoded == null) {
      // 키가 없거나 손상된(또는 암호화 이전의 평문) 저장본이다 — 읽을 수 없는 행을 남겨 두지 않는다.
      await (_database.delete(
        _database.cachedRosters,
      )..where((t) => t.runId.equals(runId))).go();
      return null;
    }
    return (json: decoded, savedAt: row.savedAt);
  }

  Map<String, dynamic>? _tryDecode(String clear) {
    try {
      final decoded = jsonDecode(clear);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// 저장본을 **먼저** 지우고 키를 지운다 — 행 삭제가 실패해도 키는 지운다(`finally`).
  @override
  Future<void> clear() async {
    try {
      await _database.delete(_database.cachedRosters).go();
    } finally {
      await _cipher.deleteKey();
    }
  }
}
