import 'package:manager_app/core/network/guard.dart';
import 'package:manager_app/features/emergency/data/emergency_api.dart';
import 'package:manager_app/features/emergency/data/models/emergency_item.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_request.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_result.dart';
import 'package:manager_app/features/emergency/domain/emergency_repository.dart';
import 'package:manager_app/features/offline_queue/domain/offline_queue_repository.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';

class EmergencyRepositoryImpl implements EmergencyRepository {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(DelayRepositoryImpl 과 같은 이유).
  const EmergencyRepositoryImpl({
    required EmergencyApi api,
    required OfflineQueueRepository offlineQueue,
  })
    // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을 쓴다.
    // ignore: prefer_initializing_formals
    : _api = api,
       // 위와 같은 이유.
       // ignore: prefer_initializing_formals
       _offlineQueue = offlineQueue;

  final EmergencyApi _api;
  final OfflineQueueRepository _offlineQueue;

  @override
  Future<SendOutcome<EmergencyRaiseResult>> raise({
    required String runId,
    required EmergencyRaiseRequest request,
  }) => _offlineQueue.sendOrQueue(
    endpoint: '/runs/$runId/emergency',
    method: 'POST',
    payload: request.toJson(),
    send: () => guardDio(() => _api.raise(runId: runId, request: request)),
  );

  @override
  Future<void> cancel({required String runId, required String emergencyId}) =>
      guardDio(() => _api.cancel(runId: runId, emergencyId: emergencyId));

  @override
  Future<EmergencyListResponse> fetchList({required String runId}) =>
      guardDio(() => _api.list(runId: runId));
}
