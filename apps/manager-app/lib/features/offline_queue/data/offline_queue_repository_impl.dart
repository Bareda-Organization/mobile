import 'dart:convert';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show ComparableExpr, OrderingTerm, Value;
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:manager_app/features/offline_queue/domain/offline_queue_repository.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';

/// `OfflineQueueRepository` 구현 — drift(로컬 저장) + `Dio`(재생 전송).
///
/// 재생은 `guardDio` 를 거치지 않는다 — 성공 여부만 필요하고, 실패를 화면에
/// 보여줄 `Failure` 로 옮길 필요가 없다(재생은 화면 액션이 아니라 배치성
/// 동작이라 결과는 `ReplayResult` 집계로 충분하다).
///
/// 큐에 쌓는 경우는 두 가지다 — 서버에 닿지 못한 경우([NetworkFailure])와, 서버가
/// 응답했지만 지금은 못 받는 5xx(백엔드 재기동 중 nginx 502·풀 고갈 500). 둘 다
/// `client_key` 가 서버의 중복 처리를 막으므로 다시 보내도 안전하다.
class OfflineQueueRepositoryImpl implements OfflineQueueRepository {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(DelayRepositoryImpl 과 같은 이유).
  new({
    required OfflineQueueDatabase database,
    required Dio dio,
    Clock clock = const SystemClock(),
  })
    // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을 쓴다.
    // ignore: prefer_initializing_formals
    : _database = database,
       // 위와 같은 이유.
       // ignore: prefer_initializing_formals
       _dio = dio,
       // 위와 같은 이유.
       // ignore: prefer_initializing_formals
       _clock = clock;

  /// 한 행이 5xx 로 재생에 실패하는 횟수 상한 — 닿으면 영구 실패로 재생에서 뺀다. 주기 재생(30초)이 한 번씩
  /// 세므로 약 5분이다. **비상 신고에는 적용하지 않는다**(Ruling 616).
  static const maxAttempts = 10;

  /// 5xx 를 받은 행이 쌓인 지 이만큼 지났으면 횟수와 무관하게 영구 실패로 뺀다. 통신 두절만 이어진 행에는
  /// 적용하지 않는다 — 터널·음영이 길다고 쌓아 둔 승하차를 버리지 않는다. 비상 신고에도 적용하지 않는다(Ruling 616).
  static const maxAge = Duration(minutes: 30);

  final OfflineQueueDatabase _database;
  final Dio _dio;
  final Clock _clock;

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
      // 새 요청 앞의 재생은 시도 횟수에 넣지 않는다 — 서버가 죽은 동안 학생을 연달아 누르면 눌렀을 뿐인데
      // 머리 행이 곧바로 영구 실패가 된다. 횟수는 주기 재생·수동 재시도만 센다.
      final replay = await _replay(countAttempts: false);
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
    } on Failure catch (failure) {
      // 서버가 지금 못 받는 경우에만 큐에 쌓는다 — `ApiFailure`(예:
      // `422 VALIDATION_FAILED`)는 재시도해도 같은 응답이라 큐 대상이 아니다.
      // 아니면 호출부가 그대로 받도록 다시 던진다.
      if (!_isServerUnavailable(failure)) rethrow;
      await _enqueue(endpoint: endpoint, method: method, payload: payload);
      return const Queued();
    }
  }

  /// 다시 보내면 통과할 수 있는 실패 — 서버에 닿지 못했거나, 서버가 5xx 로
  /// 응답했다. 5xx 본문이 JSON 이면 `ApiFailure`, nginx 의 HTML 502·504 면
  /// `UnknownFailure` 로 오며 둘 다 상태 코드를 들고 있다.
  bool _isServerUnavailable(Failure failure) => switch (failure) {
    NetworkFailure() => true,
    ApiFailure(:final statusCode) => _isServerError(statusCode),
    UnknownFailure(:final statusCode) => _isServerError(statusCode),
    UnauthenticatedFailure() => false,
  };

  /// 5xx 전부 — 이 서버가 내는 것은 500·502·503·504 지만, Cloudflare
  /// Tunnel(스테이징)은 520~530 으로도 답한다. 쌓는 쪽과 재생의 시도 횟수 쪽이
  /// 이 한 기준을 쓴다.
  bool _isServerError(int? status) => status != null && status >= 500;

  /// 재생 대상(영구 실패가 아닌) 행이 있는지.
  Future<bool> _hasPending() async =>
      (await (_database.select(_database.pendingRequests)
                ..where((t) => t.attempts.isSmallerThanValue(maxAttempts))
                ..limit(1))
              .get())
          .isNotEmpty;

  /// 재생 대상 행 — 쌓인 순서(id)로 읽는다. 영구 실패 행은 빠진다.
  Future<List<PendingRequest>> _activeRows() =>
      (_database.select(_database.pendingRequests)
            ..where((t) => t.attempts.isSmallerThanValue(maxAttempts))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();

  Future<void> _enqueue({
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
  }) async {
    if (await _isDuplicate(endpoint, method, payload)) return;
    await _database
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
  }

  /// 같은 학생(같은 [endpoint])에게 같은 승하차 `status` 가 이미 기다리고 있으면 중복이다(R46) — 두 번 눌러도
  /// 재생 때 같은 처리가 두 번 나가지 않게 한다. 도착 처리(`/stops/{stopId}/arrive`)는 본문이 없어 같은 승하차지의
  /// 같은 요청이 이미 기다리고 있으면 중복이다(859). 그 밖에 `status` 가 없는 요청(비상 발신은 "상황 변화마다
  /// 재발신이 정상", §4.14)은 중복으로 보지 않는다. 영구 실패 행은 기다리는 것이 아니라 다시 눌러 새로 보낼 수 있다.
  Future<bool> _isDuplicate(
    String endpoint,
    String method,
    Map<String, dynamic> payload,
  ) async {
    final status = payload['status'];
    final isArrive = PendingRequestSummary.isArriveEndpoint(endpoint);
    if (status == null && !isArrive) return false;
    // `where` 를 두 번 부르면 AND 로 묶인다.
    final rows =
        await (_database.select(_database.pendingRequests)
              ..where((t) => t.endpoint.equals(endpoint))
              ..where((t) => t.method.equals(method))
              ..where((t) => t.attempts.isSmallerThanValue(maxAttempts)))
            .get();
    if (isArrive) return rows.isNotEmpty;
    return rows.any((row) {
      final body = jsonDecode(row.payload);
      return body is Map<String, dynamic> && body['status'] == status;
    });
  }

  @override
  Future<List<PendingRequestSummary>> fetchPending() async {
    final rows = await (_database.select(
      _database.pendingRequests,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    return rows
        .map(
          (row) => PendingRequestSummary(
            id: row.id,
            endpoint: row.endpoint,
            method: row.method,
            payload: row.payload,
            createdAt: row.createdAt,
            failed: row.attempts >= maxAttempts,
          ),
        )
        .toList();
  }

  @override
  Future<ReplayResult> replayPending() => _replay(countAttempts: true);

  /// [countAttempts] 가 참이면 서버가 5xx 로 응답한 머리 행의 시도 횟수를 올린다(상한이면 영구 실패로 빼고
  /// 같은 재생에서 뒤 행을 이어 보낸다). 거짓이면 세지 않고 기존처럼 첫 실패에서 멈춘다.
  Future<ReplayResult> _replay({required bool countAttempts}) async {
    final rows = await _activeRows();
    var succeeded = 0;
    var droppedPermanently = 0;
    var failedPermanently = 0;
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
        if (_isAlreadyArrived(row, exception)) {
          // 서버가 이미 처리한 도착이다(응답만 잃은 채 재전송) — 같은 결과를 원했으므로 성공으로 센다(859).
          await _deleteRow(row.id);
          succeeded++;
          continue;
        }
        if (_isPermanentRejection(exception)) {
          // 서버가 확정 거절했다 — 다시 보내도 같은 결과라 큐에서 뺀다.
          await _deleteRow(row.id);
          droppedPermanently++;
          continue;
        }
        if (_isServerError(exception.response?.statusCode)) {
          // 비상 신고는 영구 실패로 빼지 않는다(Ruling 616) — 시도 횟수도 나이도 세지 않고 성공하거나 사용자가 큐
          // 화면에서 지울 때까지 남긴다. 상한이 없는 대신 뒤 행은 이어 보낸다 — 비상이 승하차를 영구히 막지 않게.
          if (PendingRequestSummary.isEmergencyEndpoint(row.endpoint)) {
            continue;
          }
          // 서버가 5xx 로 응답했다 — 이 행이 계속 5xx 를 받으면 행 쪽 문제일 수 있다. 상한에 닿으면 영구 실패로
          // 빼고(큐 화면에 남는다) 뒤 행을 이어 보낸다. 안 닿았으면 아래에서 멈춘다.
          if (countAttempts && await _recordServerError(row)) {
            failedPermanently++;
            continue;
          }
        }
        // 아직 두절이거나 서버가 일시적으로 못 받는 상태(5xx·429·401)다. 남은
        // 행도 같은 타임아웃을 되풀이할 뿐이고, 중간 건만 성공하면 큐 안의
        // 순서가 뒤집히므로 여기서 멈춘다 — 남은 행은 다음 재생이 이어 보낸다.
        break;
      }
    }
    final stillPending =
        rows.length - succeeded - droppedPermanently - failedPermanently;
    return ReplayResult(
      succeeded: succeeded,
      stillPending: stillPending,
      droppedPermanently: droppedPermanently,
      failedPermanently: failedPermanently,
    );
  }

  /// 이 행이 5xx 를 한 번 더 받았다 — 시도 횟수를 올리고, 횟수나 나이가 상한에 닿으면 영구 실패로 굳힌다.
  /// 나이 상한으로 굳힐 때도 같은 표식(`attempts == maxAttempts`)을 써서 영구 실패 여부가 컬럼 하나로 읽힌다.
  /// 영구 실패가 됐으면 `true`.
  Future<bool> _recordServerError(PendingRequest row) async {
    final attempts = row.attempts + 1;
    final exhausted =
        attempts >= maxAttempts ||
        _clock.now().difference(row.createdAt) >= maxAge;
    await (_database.update(
      _database.pendingRequests,
    )..where((t) => t.id.equals(row.id))).write(
      PendingRequestsCompanion(
        attempts: Value(exhausted ? maxAttempts : attempts),
      ),
    );
    return exhausted;
  }

  @override
  Future<void> cancel(int id) => _deleteRow(id);

  @override
  Future<void> clear() => _database.delete(_database.pendingRequests).go();

  /// 도착 처리 재전송에 서버가 `403 DUPLICATE_ARRIVE`(같은 승하차지 재처리, API_SPEC §4.5)
  /// 로 답했는가. **403 이면서 에러 코드가 `DUPLICATE_ARRIVE`** 일 때만이다 — 403 전체를 흡수하면
  /// `403 DRIVER_ONLY`(권한 없음)까지 성공으로 삼킨다.
  bool _isAlreadyArrived(PendingRequest row, DioException exception) {
    if (!PendingRequestSummary.isArriveEndpoint(row.endpoint)) return false;
    if (exception.response?.statusCode != 403) return false;
    final data = exception.response?.data;
    final error = data is Map ? data['error'] : null;
    return error is Map && error['code'] == 'DUPLICATE_ARRIVE';
  }

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
