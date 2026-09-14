import 'package:dio/dio.dart';
import 'package:parent_app/features/route/domain/route_detail.dart';

/// API_SPEC §3.10 — `ApiClient.dio` 를 그대로 받는다.
class RouteApi {
  RouteApi({required this._dio});

  final Dio _dio;

  Future<RouteDetail> getRoute(
    String studentId, {
    DateTime? date,
    String? runId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/students/$studentId/route',
      queryParameters: {
        if (date != null) 'date': _dateOnly(date),
        'run_id': ?runId,
      },
    );
    return RouteDetail.fromJson(response.data!);
  }

  /// `date` 쿼리는 `YYYY-MM-DD` — `run_api.dart` 의 `_dateOnly` 와 같은
  /// 이유(`DateTime.toIso8601String()` 을 그대로 보내면 시각·타임존까지
  /// 붙어 서버의 `date` 파서와 어긋난다).
  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
