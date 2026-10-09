import 'dart:convert';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:drift/drift.dart' show ComparableExpr;
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:manager_app/features/roster/domain/roster_cache.dart';

/// [RosterCache] 구현 — 오프라인 대기열과 같은 기기 DB(drift)의 `cached_rosters` 표를 쓴다.
class DriftRosterCache implements RosterCache {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을 쓴다.
  const new({
    required OfflineQueueDatabase database,
    Clock clock = const SystemClock(),
  })
    // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을 쓴다.
    // ignore: prefer_initializing_formals
    : _database = database,
      // 위와 같은 이유.
      // ignore: prefer_initializing_formals
      _clock = clock;

  /// 이 기간이 지난 저장본은 새로 저장할 때 치운다 — 지난 운행의 명단을 기기에 계속 쌓아 두지 않는다.
  static const keepFor = Duration(days: 2);

  final OfflineQueueDatabase _database;
  final Clock _clock;

  @override
  Future<void> save(String runId, Map<String, dynamic> json) async {
    final now = _clock.now();
    await _database
        .into(_database.cachedRosters)
        .insertOnConflictUpdate(
          CachedRostersCompanion.insert(
            runId: runId,
            payload: jsonEncode(json),
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
    final decoded = jsonDecode(row.payload);
    if (decoded is! Map<String, dynamic>) return null;
    return (json: decoded, savedAt: row.savedAt);
  }

  @override
  Future<void> clear() => _database.delete(_database.cachedRosters).go();
}
