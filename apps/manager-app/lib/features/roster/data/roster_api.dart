import 'package:dio/dio.dart';
import 'package:manager_app/features/roster/data/models/boarding_update_request.dart';
import 'package:manager_app/features/roster/data/models/no_show_contact_request.dart';
import 'package:manager_app/features/roster/data/models/revert_result.dart';
import 'package:manager_app/features/roster/data/models/rider_update_result.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';

/// API_SPEC §4.2·§4.6·§4.7·§4.8.
class RosterApi {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(AuthRepositoryImpl 과 같은 이유).
  // ignore: prefer_initializing_formals
  RosterApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<RosterResponse> fetchRoster(String runId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/runs/$runId/roster',
    );
    return RosterResponse.fromJson(response.data!);
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
}
