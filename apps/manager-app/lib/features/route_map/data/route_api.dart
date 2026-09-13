import 'package:dio/dio.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';

/// API_SPEC §4.3.
class RouteApi {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(RosterApi 와 같은 이유).
  // ignore: prefer_initializing_formals
  RouteApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<RouteResponse> fetchRoute(String runId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/runs/$runId/route',
    );
    return RouteResponse.fromJson(response.data!);
  }
}
