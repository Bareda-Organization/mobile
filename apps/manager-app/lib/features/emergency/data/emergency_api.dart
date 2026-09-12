import 'package:dio/dio.dart';
import 'package:manager_app/features/emergency/data/models/emergency_item.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_request.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_result.dart';

/// API_SPEC §4.14(발신·취소)·§4.15(목록).
class EmergencyApi {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(DelayApi 와 같은 이유).
  // ignore: prefer_initializing_formals
  EmergencyApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<EmergencyRaiseResult> raise({
    required String runId,
    required EmergencyRaiseRequest request,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/runs/$runId/emergency',
      data: request.toJson(),
    );
    return EmergencyRaiseResult.fromJson(response.data!);
  }

  /// §4.14 취소 — 응답 `204`(본문 없음).
  Future<void> cancel({
    required String runId,
    required String emergencyId,
  }) async {
    await _dio.delete<void>('/runs/$runId/emergency/$emergencyId');
  }

  Future<EmergencyListResponse> list({required String runId}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/runs/$runId/emergencies',
    );
    return EmergencyListResponse.fromJson(response.data!);
  }
}
