import 'package:parent_app/core/runs/domain/run_intent_result.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';

/// 화면이 보는 회차 계약 — §3.5·§3.6.
abstract interface class RunRepository {
  /// §3.5. [date] 를 생략하면 서버 기본값(당일).
  Future<List<StudentRun>> getRuns(String studentId, {DateTime? date});

  /// §3.6 — `riding=false` 는 미탑승 의사. 3구간 판정은 서버가 한다.
  Future<RunIntentResult> updateIntent(
    String studentId,
    String runId, {
    required bool riding,
  });
}
