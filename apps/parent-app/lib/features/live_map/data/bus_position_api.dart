import 'package:dio/dio.dart';
import 'package:parent_app/features/live_map/domain/bus_position.dart';

/// API_SPEC §3.11 — `ApiClient.dio` 를 그대로 받는다(`route_api.dart` 와
/// 같은 패턴).
class BusPositionApi {
  new({required this._dio});

  final Dio _dio;

  Future<BusPosition> getBusPosition(String studentId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/students/$studentId/bus-position',
    );
    return BusPosition.fromJson(response.data!);
  }
}
