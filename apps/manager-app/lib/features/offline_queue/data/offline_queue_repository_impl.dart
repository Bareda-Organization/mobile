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
    // 복구 시 자동 동기화(M-06) — 큐가 남아 있으면 **새 요청보다 먼저**
    // 흘려보낸다. 순서를 뒤집으면 오프라인에서 쌓인 옛 처리가 복구 후의 새
    // 처리를 덮어쓴다(오프라인 '탑승' → 복구 후 '되돌리기' → 재생이 다시
    // '탑승').
    if (await _hasPending()) {
      final replay = await replayPending();
      if (replay.stillPending > 0) {
        // 아직 두절이다 — 새 요청으로 같은 타임아웃을 한 번 더 기다릴
        // 이유가 없다. 시도 없이 큐로 보낸다.
        await _enqueue(endpoint: endpoint, method: method, payload: payload);
        return const Queued();
      }
    }
    try {
      final result = await send();
      return Sent(result);
    } on NetworkFailure {
      // 서버에 닿지 못한 경우에만 큐에 쌓는다 — `ApiFailure`(예:
      // `422 VALIDATION_FAILED`)는 재시도해도 같은 응답이라 큐 대상이
      // 아니다. 호출부가 그 경우 그대로 다시 던지도록 이 catch 는
      // `NetworkFailure` 하나만 잡는다.
      await _enqueue(endpoint: endpoint, method: method, payload: payload);
      return const Queued();
    }
  }

  Future<bool> _hasPending() async {
    final rows = await (_database.select(
      _database.pendingRequests,
    )..limit(1)).get();
    return rows.isNotEmpty;
  }

  Future<void> _enqueue({
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
  }) => _database
      .into(_database.pendingRequests)
      .insert(
        PendingRequestsCompanion.insert(
          endpoint: endpoint,
          // `method` 컬럼에 기본값(`PATCH`)이 있어 생성된 `.insert()` 는 이
          // 필드를 `Value<String>` 로 받는다 — 기본값이 없는 다른 컬럼과
          // 달리 명시적으로 감싸야 한다.
          method: Value(method),
          payload: jsonEncode(payload),
        ),
      );

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
        if (_isPermanentRejection(exception)) {
          // 서버가 확정 거절했다 — 다시 보내도 같은 결과라 큐에서 뺀다.
          await _deleteRow(row.id);
          droppedPermanently++;
          continue;
        }
        // 아직 두절이거나 서버가 일시적으로 못 받는 상태(5xx·429·401)다. 남은
        // 행도 같은 타임아웃을 되풀이할 뿐이고, 중간 건만 성공하면 큐 안의
        // 순서가 뒤집히므로 여기서 멈춘다 — 남은 행은 다음 재생이 이어 보낸다.
        break;
      }
    }
    final stillPending = rows.length - succeeded - droppedPermanently;
    return ReplayResult(
      succeeded: succeeded,
      stillPending: stillPending,
      droppedPermanently: droppedPermanently,
    );
  }

  @override
  Future<void> clear() => _database.delete(_database.pendingRequests).go();

  /// 다시 보내도 같은 결과인 4xx 만 확정 거절이다. 401(재발급 실패)·408·429
  /// 와 5xx·비JSON 프록시 오류는 재시도하면 통과할 수 있어 행을 남긴다.
  bool _isPermanentRejection(DioException exception) {
    if (exception.type != DioExceptionType.badResponse) return false;
    final status = exception.response?.statusCode ?? 0;
    return status >= 400 &&
        status < 500 &&
        status != 401 &&
        status != 408 &&
        status != 429;
  }

  Future<void> _deleteRow(int id) => (_database.delete(
    _database.pendingRequests,
  )..where((t) => t.id.equals(id))).go();
}
