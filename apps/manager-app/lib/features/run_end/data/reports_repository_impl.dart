import 'package:manager_app/core/network/guard.dart';
import 'package:manager_app/features/run_end/data/models/report_request.dart';
import 'package:manager_app/features/run_end/data/models/report_result.dart';
import 'package:manager_app/features/run_end/data/reports_api.dart';
import 'package:manager_app/features/run_end/domain/reports_repository.dart';

/// [ReportsRepository] 구현 — `guardDio` 로 `DioException` 을 `Failure` 로
/// 옮긴다.
class ReportsRepositoryImpl implements ReportsRepository {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(AuthRepositoryImpl 과 같은 이유).
  // ignore: prefer_initializing_formals
  const new({required ReportsApi api}) : _api = api;

  final ReportsApi _api;

  @override
  Future<ReportResult> submitReport({
    required String runId,
    required ReportRequest request,
  }) => guardDio(() => _api.submitReport(runId: runId, request: request));
}
