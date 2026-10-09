import 'package:manager_app/core/network/guard.dart';
import 'package:manager_app/features/drive_mode/data/drive_mode_api.dart';
import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
import 'package:manager_app/features/drive_mode/data/models/start_run_result.dart';
import 'package:manager_app/features/drive_mode/domain/drive_mode_repository.dart';
import 'package:manager_app/features/offline_queue/domain/offline_queue_repository.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';

/// [DriveModeRepository] 구현 — `guardDio` 로 `DioException` 을 `Failure`
/// 로 옮긴다(`ManagerRunRepositoryImpl` 과 같은 패턴). 도착 처리는 오프라인 큐를 거친다(`Ruling 859`).
class DriveModeRepositoryImpl implements DriveModeRepository {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(AuthRepositoryImpl 과 같은 이유).
  const new({
    required DriveModeApi api,
    required OfflineQueueRepository offlineQueue,
  })
    // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을 쓴다.
    // ignore: prefer_initializing_formals
    : _api = api,
       // 위와 같은 이유.
       // ignore: prefer_initializing_formals
       _offlineQueue = offlineQueue;

  final DriveModeApi _api;
  final OfflineQueueRepository _offlineQueue;

  @override
  Future<StartRunResult> startRun(String runId) =>
      guardDio(() => _api.startRun(runId));

  @override
  Future<SendOutcome<ArriveStopResult>> arriveStop({
    required String runId,
    required String stopId,
  }) => _offlineQueue.sendOrQueue(
    endpoint: '/runs/$runId/stops/$stopId/arrive',
    method: 'POST',
    // 도착 처리는 본문이 없다(§4.5) — 중복은 서버가 `DUPLICATE_ARRIVE` 로 가린다.
    payload: const {},
    send: () => guardDio(() => _api.arriveStop(runId: runId, stopId: stopId)),
  );
}
