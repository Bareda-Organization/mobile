import 'package:baraeda_core/baraeda_core.dart';
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
import 'package:manager_app/features/roster/domain/roster_cache.dart';
import 'package:manager_app/features/roster/domain/roster_repository.dart';

/// [RosterRepository] 구현 — `guardDio` 로 `DioException` 을 `Failure` 로
/// 옮긴다. 승하차 갱신만 `_offlineQueue` 를 거친다(§1.7 M-06, UF-E-07) —
/// 나머지 쓰기(되돌리기·연락 기록·변경 확인)는 이번 라운드의 큐 대상이
/// 아니다(문서상 그 예시로 명시된 것은 승하차 처리뿐이다). 명단 조회는 받은 본문을
/// `_cache` 에 저장하고, 서버가 응답하지 못하면 그 저장본으로 돌아선다(M-M3).
class RosterRepositoryImpl implements RosterRepository {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(AuthRepositoryImpl 과 같은 이유).
  const new({
    required RosterApi api,
    required OfflineQueueRepository offlineQueue,
    required RosterCache cache,
    bool Function() isSignedIn = _alwaysSignedIn,
  })
    // 위와 같은 이유.
    // ignore: prefer_initializing_formals
    : _api = api,
       // 위와 같은 이유.
       // ignore: prefer_initializing_formals
       _offlineQueue = offlineQueue,
       // 위와 같은 이유.
       // ignore: prefer_initializing_formals
       _cache = cache,
       // 위와 같은 이유.
       // ignore: prefer_initializing_formals
       _isSignedIn = isSignedIn;

  static bool _alwaysSignedIn() => true;

  final RosterApi _api;
  final OfflineQueueRepository _offlineQueue;
  final RosterCache _cache;

  /// 저장 직전에 아직 로그인한 계정이 있는지 — 로그아웃 직전에 보낸 요청의 응답이 정리(`RosterCache.clear`) 뒤에
  /// 도착해도 지운 명단을 다시 저장하지 않는다(M-2).
  final bool Function() _isSignedIn;

  @override
  Future<RosterResponse> fetchRoster(String runId) async {
    try {
      final json = await guardDio(() => _api.fetchRosterJson(runId));
      final roster = RosterResponse.fromJson(json);
      // 저장은 덤이다 — 저장이 실패해도 방금 받은 명단을 보이는 일을 막지 않는다.
      await _saveQuietly(runId, json);
      return roster;
    } on Failure catch (failure) {
      // 서버가 응답하지 못할 때만 저장본으로 돌아선다. 4xx(권한 없음 · 회차 없음)는 서버의 판단이라 낡은
      // 저장본으로 덮지 않는다.
      if (!_isServerUnavailable(failure)) rethrow;
      final saved = await _cache.read(runId);
      if (saved == null) rethrow;
      return RosterResponse.fromJson(saved.json, cachedAt: saved.savedAt);
    }
  }

  Future<void> _saveQuietly(String runId, Map<String, dynamic> json) async {
    if (!_isSignedIn()) return;
    try {
      await _cache.save(runId, json);
    } on Object {
      // 저장소 오류는 조회 결과에 영향을 주지 않는다.
    }
  }

  /// 오프라인 큐가 "다시 보내면 통과할 수 있다" 고 보는 실패와 같은 기준 — 서버에 닿지 못했거나 5xx 다.
  bool _isServerUnavailable(Failure failure) => switch (failure) {
    NetworkFailure() => true,
    ApiFailure(:final statusCode) => statusCode >= 500,
    UnknownFailure(:final statusCode) => (statusCode ?? 0) >= 500,
    UnauthenticatedFailure() => false,
  };

  @override
  Future<SendOutcome<RiderUpdateResult>> updateRiderStatus({
    required String runId,
    required String riderId,
    required BoardingUpdateRequest request,
  }) => _offlineQueue.sendOrQueue(
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
  Future<AckChangesResult> ackChanges({required String runId}) =>
      guardDio(() => _api.ackChanges(runId: runId));
}
