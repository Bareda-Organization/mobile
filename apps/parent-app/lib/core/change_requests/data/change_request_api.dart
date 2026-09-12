import 'package:dio/dio.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';

/// API_SPEC §3.8·§3.9.
class ChangeRequestApi {
  ChangeRequestApi({required this._dio});

  final Dio _dio;

  Future<ChangeRequestCreateResult> createChangeRequest(
    String studentId, {
    required ChangeRequestType type,
    required String runId,
    String? newAddress,
    String? reason,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/students/$studentId/change-requests',
      data: {
        'type': type.wireValue,
        'run_id': runId,
        'new_address': ?newAddress,
        'reason': ?reason,
      },
    );
    return ChangeRequestCreateResult.fromJson(response.data!);
  }

  Future<ChangeRequestPage> getChangeRequests(String studentId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/students/$studentId/change-requests',
    );
    return ChangeRequestPage.fromJson(response.data!);
  }
}
