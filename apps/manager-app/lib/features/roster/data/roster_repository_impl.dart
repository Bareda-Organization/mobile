import 'package:manager_app/core/network/guard.dart';
import 'package:manager_app/features/roster/data/models/ack_changes_result.dart';
import 'package:manager_app/features/roster/data/models/boarding_update_request.dart';
import 'package:manager_app/features/roster/data/models/no_show_contact_request.dart';
import 'package:manager_app/features/roster/data/models/revert_result.dart';
import 'package:manager_app/features/roster/data/models/rider_update_result.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/data/roster_api.dart';
import 'package:manager_app/features/roster/domain/roster_repository.dart';

/// [RosterRepository] 구현 — `guardDio` 로 `DioException` 을 `Failure` 로
/// 옮긴다.
class RosterRepositoryImpl implements RosterRepository {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(AuthRepositoryImpl 과 같은 이유).
  // ignore: prefer_initializing_formals
  const RosterRepositoryImpl({required RosterApi api}) : _api = api;

  final RosterApi _api;

  @override
  Future<RosterResponse> fetchRoster(String runId) =>
      guardDio(() => _api.fetchRoster(runId));

  @override
  Future<RiderUpdateResult> updateRiderStatus({
    required String runId,
    required String riderId,
    required BoardingUpdateRequest request,
  }) => guardDio(
    () => _api.updateRiderStatus(
      runId: runId,
      riderId: riderId,
      request: request,
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
