import 'package:dio/dio.dart';
import 'package:manager_app/features/roster/data/models/ack_changes_result.dart';
import 'package:manager_app/features/roster/data/models/boarding_update_request.dart';
import 'package:manager_app/features/roster/data/models/no_show_contact_request.dart';
import 'package:manager_app/features/roster/data/models/revert_result.dart';
import 'package:manager_app/features/roster/data/models/rider_update_result.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';

/// API_SPEC §4.2·§4.2.1·§4.6·§4.7·§4.8·§4.11.
class RosterApi {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(AuthRepositoryImpl 과 같은 이유).
  // ignore: prefer_initializing_formals
  new({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<RosterResponse> fetchRoster(String runId) async =>
      RosterResponse.fromJson(await fetchRosterJson(runId));

  /// §4.2 응답 본문 그대로 — 로컬 저장(`RosterCache`)이 파싱 전 본문을 담는다.
  Future<Map<String, dynamic>> fetchRosterJson(String runId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/runs/$runId/roster',
    );
    return response.data!;
  }

  /// §4.2.1 — 보호자 원번호 1건. 연결된 보호자가 없으면 `null`.
  Future<String?> fetchGuardianPhone({
    required String runId,
    required String riderId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/runs/$runId/riders/$riderId/guardian-phone',
    );
    return response.data!['guardian_phone'] as String?;
  }

  Future<RiderUpdateResult> updateRiderStatus({
    required String runId,
    required String riderId,
    required BoardingUpdateRequest request,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/runs/$runId/riders/$riderId',
      data: request.toJson(),
    );
    return RiderUpdateResult.fromJson(response.data!);
  }

  Future<RevertResult> revertRiderStatus({
    required String runId,
    required String riderId,
    String? reason,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/runs/$runId/riders/$riderId/revert',
      data: {'reason': ?reason},
    );
    return RevertResult.fromJson(response.data!);
  }

  Future<void> recordNoShowContact({
    required String runId,
    required String riderId,
    required NoShowContactRequest request,
  }) async {
    await _dio.post<void>(
      '/runs/$runId/riders/$riderId/no-show-contacts',
      data: request.toJson(),
    );
  }

  /// §4.11 — 요청 본문 없음, 현재 노선 버전 단위 전건 확인(Ruling 344). 변경 건 하나하나를
  /// 골라 확인하는 저장 구조가 스키마에 없어(`acked_route_version_id` 가 버전 1개만 가리킴)
  /// 이 API 자체가 그런 값을 받지 않는다.
  Future<AckChangesResult> ackChanges({required String runId}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/runs/$runId/ack-changes',
    );
    return AckChangesResult.fromJson(response.data!);
  }
}
