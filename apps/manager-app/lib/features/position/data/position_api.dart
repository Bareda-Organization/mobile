import 'package:dio/dio.dart';
import 'package:manager_app/features/position/data/models/position_request.dart';

/// API_SPEC §4.12.
class PositionApi {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(DelayApi 와 같은 이유).
  // ignore: prefer_initializing_formals
  PositionApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<void> sendPosition({
    required String runId,
    required PositionRequest request,
  }) async {
    await _dio.post<void>('/runs/$runId/position', data: request.toJson());
  }
}
