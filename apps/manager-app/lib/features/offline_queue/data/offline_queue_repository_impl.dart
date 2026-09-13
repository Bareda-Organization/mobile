import 'dart:convert';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:manager_app/features/offline_queue/domain/offline_queue_repository.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';

/// `OfflineQueueRepository` 구현 — drift(로컬 저장) + `Dio`(재생 전송).
///
/// 재생은 `guardDio` 를 거치지 않는다 — 성공 여부만 필요하고, 실패를 화면에
/// 보여줄 `Failure` 로 옮길 필요가 없다(재생은 화면 액션이 아니라 배치성
/// 동작이라 결과는 `ReplayResult` 집계로 충분하다).
class OfflineQueueRepositoryImpl implements OfflineQueueRepository {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(DelayRepositoryImpl 과 같은 이유).
  OfflineQueueRepositoryImpl({
    required OfflineQueueDatabase database,
    required Dio dio,
  })
    // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을 쓴다.
    // ignore: prefer_initializing_formals
    : _database = database,
       // 위와 같은 이유.
       // ignore: prefer_initializing_formals
       _dio = dio;

  final OfflineQueueDatabase _database;
  final Dio _dio;

  @override
  Future<SendOutcome<T>> sendOrQueue<T>({
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
    required Future<T> Function() send,
  }) async {
    try {
      final result = await send();
      return Sent(result);
    } on NetworkFailure {
      // 서버에 닿지 못한 경우에만 큐에 쌓는다 — `ApiFailure`(예:
      // `422 VALIDATION_FAILED`)는 재시도해도 같은 응답이라 큐 대상이
      // 아니다. 호출부가 그 경우 그대로 다시 던지도록 이 catch 는
      // `NetworkFailure` 하나만 잡는다.
      await _database
          .into(_database.pendingRequests)
          .insert(
            PendingRequestsCompanion.insert(
              endpoint: endpoint,
              // `method` 컬럼에 기본값(`PATCH`)이 있어 생성된 `.insert()` 는
              // 이 필드를 `Value<String>` 로 받는다 — 기본값이 없는 다른
              // 컬럼과 달리 명시적으로 감싸야 한다.
              method: Value(method),
              payload: jsonEncode(payload),
            ),
          );
      return const Queued();
    }
  }

  @override
  Future<List<PendingRequestSummary>> fetchPending() async {
    final rows = await _database.select(_database.pendingRequests).get();
    return rows
        .map(
          (row) => PendingRequestSummary(
            id: row.id,
            endpoint: row.endpoint,
            method: row.method,
            createdAt: row.createdAt,
          ),
        )
        .toList();
  }

  @override
  Future<ReplayResult> replayPending() async {
    final rows = await _database.select(_database.pendingRequests).get();
    var succeeded = 0;
    var droppedPermanently = 0;
    for (final row in rows) {
      try {
        await _dio.request<dynamic>(
          row.endpoint,
          data: jsonDecode(row.payload),
          options: Options(method: row.method),
        );
        await _deleteRow(row.id);
        succeeded++;
      } on DioException catch (exception) {
        if (mapDioExceptionToFailure(exception) is! NetworkFailure) {
          // 서버가 이미 응답했다 — 다시 보내도 같은 결과라 큐에서 뺀다.
          await _deleteRow(row.id);
          droppedPermanently++;
        }
        // NetworkFailure 면 행을 그대로 두어 다음 재생을 기다린다.
      }
    }
    final stillPending = rows.length - succeeded - droppedPermanently;
    return ReplayResult(
      succeeded: succeeded,
      stillPending: stillPending,
      droppedPermanently: droppedPermanently,
    );
  }

  Future<void> _deleteRow(int id) => (_database.delete(
    _database.pendingRequests,
  )..where((t) => t.id.equals(id))).go();
}
