import 'package:dio/dio.dart';
import 'package:manager_app/features/delay/data/models/delay_request.dart';
import 'package:manager_app/features/delay/data/models/delay_result.dart';

/// API_SPEC §4.9.
class DelayApi {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(AuthRepositoryImpl 과 같은 이유).
  // ignore: prefer_initializing_formals
  DelayApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<DelayResult> sendDelay({
    required String runId,
    required DelayRequest request,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/runs/$runId/delay',
      data: request.toJson(),
    );
    return DelayResult.fromJson(response.data!);
  }
}
