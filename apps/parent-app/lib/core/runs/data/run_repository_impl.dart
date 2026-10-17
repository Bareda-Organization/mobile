import 'package:baraeda_core/baraeda_core.dart';
import 'package:parent_app/core/runs/data/run_api.dart';
import 'package:parent_app/core/runs/domain/run_intent_result.dart';
import 'package:parent_app/core/runs/domain/run_repository.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';

class RunRepositoryImpl implements RunRepository {
  const new({required this._runApi});

  final RunApi _runApi;

  @override
  Future<List<StudentRun>> getRuns(String studentId, {DateTime? date}) =>
      guardDio(() => _runApi.getRuns(studentId, date: date));

  @override
  Future<RunIntentResult> updateIntent(
    String studentId,
    String runId, {
    required bool riding,
  }) => guardDio(() => _runApi.updateIntent(studentId, runId, riding: riding));
}
