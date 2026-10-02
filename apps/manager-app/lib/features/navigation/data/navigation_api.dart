import 'package:dio/dio.dart';
import 'package:manager_app/features/navigation/data/models/navigation_route.dart';
import 'package:manager_app/features/navigation/data/models/navigation_scope.dart';

/// API_SPEC §4.16.
class NavigationApi {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을 쓴다(RouteApi 와 같은 이유).
  // ignore: prefer_initializing_formals
  new({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// [scope] 범위의 경로를 받는다 — `remaining` 이면 서버가 공급자 상한만큼 잘라 준다.
  Future<NavigationRoute> fetch(String runId, NavigationScope scope) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/runs/$runId/navigation',
      queryParameters: {'scope': scope.name},
    );
    return NavigationRoute.fromJson(response.data!);
  }
}
