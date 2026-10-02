import 'package:dio/dio.dart';
import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
import 'package:manager_app/features/drive_mode/data/models/start_run_result.dart';

/// API_SPEC §4.4·§4.5 — 두 호출 모두 본문이 없다.
class DriveModeApi {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(AuthRepositoryImpl 과 같은 이유).
  // ignore: prefer_initializing_formals
  new({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<StartRunResult> startRun(String runId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/runs/$runId/start',
    );
    return StartRunResult.fromJson(response.data!);
  }

  Future<ArriveStopResult> arriveStop({
    required String runId,
    required String stopId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/runs/$runId/stops/$stopId/arrive',
    );
    return ArriveStopResult.fromJson(response.data!);
  }
}
