import 'package:manager_app/core/network/guard.dart';
import 'package:manager_app/features/offline_queue/domain/offline_queue_repository.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/roster/data/models/ack_changes_result.dart';
import 'package:manager_app/features/roster/data/models/boarding_update_request.dart';
import 'package:manager_app/features/roster/data/models/no_show_contact_request.dart';
import 'package:manager_app/features/roster/data/models/revert_result.dart';
import 'package:manager_app/features/roster/data/models/rider_update_result.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/data/roster_api.dart';
import 'package:manager_app/features/roster/domain/roster_repository.dart';

/// [RosterRepository] 구현 — `guardDio` 로 `DioException` 을 `Failure` 로
/// 옮긴다. 승하차 갱신만 `_offlineQueue` 를 거친다(§1.7 M-06, UF-E-07) —
/// 나머지 쓰기(되돌리기·연락 기록·변경 확인)는 이번 라운드의 큐 대상이
/// 아니다(문서상 그 예시로 명시된 것은 승하차 처리뿐이다).
class RosterRepositoryImpl implements RosterRepository {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(AuthRepositoryImpl 과 같은 이유).
  const RosterRepositoryImpl({
    required RosterApi api,
    required OfflineQueueRepository offlineQueue,
  })
    // 위와 같은 이유.
    // ignore: prefer_initializing_formals
    : _api = api,
       // 위와 같은 이유.
       // ignore: prefer_initializing_formals
       _offlineQueue = offlineQueue;

  final RosterApi _api;
  final OfflineQueueRepository _offlineQueue;

  @override
  Future<RosterResponse> fetchRoster(String runId) =>
      guardDio(() => _api.fetchRoster(runId));

  @override
  Future<SendOutcome<RiderUpdateResult>> updateRiderStatus({
    required String runId,
    required String riderId,
    required BoardingUpdateRequest request,
  }) => _offlineQueue.sendOrQueue(
    clientKey: request.clientKey,
    endpoint: '/runs/$runId/riders/$riderId',
    method: 'PATCH',
    payload: request.toJson(),
    send: () => guardDio(
      () => _api.updateRiderStatus(
        runId: runId,
        riderId: riderId,
        request: request,
      ),
    ),
  );

  @override
  Future<RevertResult> revertRiderStatus({
    required String runId,
    required String riderId,
    String? reason,
  }) => guardDio(
    () => _api.revertRiderStatus(
      runId: runId,
      riderId: riderId,
      reason: reason,
    ),
  );

  @override
  Future<void> recordNoShowContact({
    required String runId,
    required String riderId,
    required NoShowContactRequest request,
  }) => guardDio(
    () => _api.recordNoShowContact(
      runId: runId,
      riderId: riderId,
      request: request,
    ),
  );

  @override
  Future<AckChangesResult> ackChanges({
    required String runId,
    List<String>? changeIds,
  }) => guardDio(() => _api.ackChanges(runId: runId, changeIds: changeIds));
}
