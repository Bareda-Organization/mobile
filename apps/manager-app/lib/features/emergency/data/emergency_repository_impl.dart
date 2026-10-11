import 'package:baraeda_core/baraeda_core.dart';
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
  const new({
    required EmergencyApi api,
    required OfflineQueueRepository offlineQueue,
    void Function()? onSessionEndedWhileSending,
  })
    // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을 쓴다.
    // ignore: prefer_initializing_formals
    : _api = api,
       // 위와 같은 이유.
       // ignore: prefer_initializing_formals
       _offlineQueue = offlineQueue,
       // 위와 같은 이유.
       // ignore: prefer_initializing_formals
       _onSessionEndedWhileSending = onSessionEndedWhileSending;

  final EmergencyApi _api;
  final OfflineQueueRepository _offlineQueue;

  /// 직접 전송 중 세션이 끝나(재발급 401 · 대기·거절 게이트 403) 신고가 대기열에도 못 들어간 채 사라질 때 부른다
  /// (887③) — 호출부가 기기 저장 안내(Ruling 886)에 그 한 건을 더한다.
  final void Function()? _onSessionEndedWhileSending;

  @override
  Future<SendOutcome<EmergencyRaiseResult>> raise({
    required String runId,
    required EmergencyRaiseRequest request,
  }) => _offlineQueue.sendOrQueue(
    endpoint: '/runs/$runId/emergency',
    method: 'POST',
    payload: request.toJson(),
    send: () async {
      try {
        return await guardDio(() => _api.raise(runId: runId, request: request));
      } on Failure catch (failure) {
        if (isSessionEndingFailure(failure)) {
          _onSessionEndedWhileSending?.call();
        }
        rethrow;
      }
    },
  );

  @override
  Future<void> cancel({required String runId, required String emergencyId}) =>
      guardDio(() => _api.cancel(runId: runId, emergencyId: emergencyId));

  @override
  Future<EmergencyListResponse> fetchList({required String runId}) =>
      guardDio(() => _api.list(runId: runId));
}
