import 'package:dio/dio.dart';
import 'package:parent_app/core/runs/domain/run_intent_result.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';

/// API_SPEC §3.5·§3.6 — `ApiClient.dio` 를 그대로 받는다.
class RunApi {
  RunApi({required this._dio});

  final Dio _dio;

  /// §3.5.
  Future<List<StudentRun>> getRuns(String studentId, {DateTime? date}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/students/$studentId/runs',
      queryParameters: {
        if (date != null) 'date': _dateOnly(date),
      },
    );
    final items = response.data?['items'] as List<dynamic>? ?? [];
    return items
        .cast<Map<String, dynamic>>()
        .map(StudentRun.fromJson)
        .toList();
  }

  /// §3.6.
  Future<RunIntentResult> updateIntent(
    String studentId,
    String runId, {
    required bool riding,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/students/$studentId/runs/$runId/intent',
      data: {'riding': riding},
    );
    return RunIntentResult.fromJson(response.data!);
  }

  /// `date` 쿼리는 `YYYY-MM-DD` — `DateTime.toIso8601String()` 을 그대로
  /// 보내면 시각·타임존까지 붙어 서버의 `date` 파서와 어긋난다.
  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
