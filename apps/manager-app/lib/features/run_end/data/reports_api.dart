import 'package:dio/dio.dart';
import 'package:manager_app/features/run_end/data/models/report_request.dart';
import 'package:manager_app/features/run_end/data/models/report_result.dart';

/// API_SPEC §4.13.
class ReportsApi {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(AuthRepositoryImpl 과 같은 이유).
  // ignore: prefer_initializing_formals
  ReportsApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<ReportResult> submitReport({
    required String runId,
    required ReportRequest request,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/runs/$runId/reports',
      data: request.toJson(),
    );
    return ReportResult.fromJson(response.data!);
  }
}
