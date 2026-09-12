import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:parent_app/core/runs/data/run_api.dart';
import 'package:parent_app/core/runs/domain/run_intent_result.dart';
import 'package:parent_app/core/runs/domain/run_repository.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';

class RunRepositoryImpl implements RunRepository {
  const RunRepositoryImpl({required this._runApi});

  final RunApi _runApi;

  @override
  Future<List<StudentRun>> getRuns(String studentId, {DateTime? date}) =>
      _guard(() => _runApi.getRuns(studentId, date: date));

  @override
  Future<RunIntentResult> updateIntent(
    String studentId,
    String runId, {
    required bool riding,
  }) => _guard(
    () => _runApi.updateIntent(studentId, runId, riding: riding),
  );

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on DioException catch (exception) {
      // Failure 는 의도적으로 Exception/Error 를 상속하지 않는다
      // (auth_repository_impl.dart 와 같은 설계 — dart:core 예외 체계를
      // 흉내 내지 않는다). 이 지점의 `only_throw_errors` 는 예외로 둔다.
      // ignore: only_throw_errors
      throw mapDioExceptionToFailure(exception);
    }
  }
}
