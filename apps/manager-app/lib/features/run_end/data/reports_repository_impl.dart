import 'package:manager_app/core/network/guard.dart';
import 'package:manager_app/features/offline_queue/domain/offline_queue_repository.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/run_end/data/models/report_request.dart';
import 'package:manager_app/features/run_end/data/models/report_result.dart';
import 'package:manager_app/features/run_end/data/reports_api.dart';
import 'package:manager_app/features/run_end/domain/reports_repository.dart';

/// [ReportsRepository] 구현 — `guardDio` 로 `DioException` 을 `Failure` 로
/// 옮긴다.
class ReportsRepositoryImpl implements ReportsRepository {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(AuthRepositoryImpl 과 같은 이유).
  const new({
    required ReportsApi api,
    required OfflineQueueRepository offlineQueue,
  })
    // 위와 같은 이유.
    // ignore: prefer_initializing_formals
    : _api = api,
       // 위와 같은 이유.
       // ignore: prefer_initializing_formals
       _offlineQueue = offlineQueue;

  final ReportsApi _api;
  final OfflineQueueRepository _offlineQueue;

  @override
  Future<SendOutcome<ReportResult>> submitReport({
    required String runId,
    required ReportRequest request,
  }) => _offlineQueue.sendOrQueue(
    endpoint: '/runs/$runId/reports',
    method: 'POST',
    payload: request.toJson(),
    send: () =>
        guardDio(() => _api.submitReport(runId: runId, request: request)),
  );
}
