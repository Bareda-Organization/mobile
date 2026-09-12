import 'package:dio/dio.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';

/// API_SPEC §4.1 — `GET /manager/runs`.
class ManagerRunApi {
  /// `dio` 는 `ApiClient.dio`(인터셉터 부착)를 그대로 받는다.
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(AuthRepositoryImpl 과 같은 이유).
  // ignore: prefer_initializing_formals
  ManagerRunApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// [date] 를 생략하면 서버 기본값(`today`)이 적용된다. 배정 회차가
  /// 없으면 서버가 빈 `items[]` 를 준다 — 에러가 아니다.
  Future<List<ManagerRun>> fetchRuns({DateTime? date}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/manager/runs',
      queryParameters: {if (date != null) 'date': _formatDate(date)},
    );
    final items = response.data?['items'] as List<dynamic>? ?? [];
    return items.cast<Map<String, dynamic>>().map(ManagerRun.fromJson).toList();
  }

  static String _formatDate(DateTime date) {
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${pad2(date.month)}-${pad2(date.day)}';
  }
}
