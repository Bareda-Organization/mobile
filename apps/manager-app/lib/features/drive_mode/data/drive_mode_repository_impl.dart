import 'package:manager_app/core/network/guard.dart';
import 'package:manager_app/features/drive_mode/data/drive_mode_api.dart';
import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
import 'package:manager_app/features/drive_mode/data/models/start_run_result.dart';
import 'package:manager_app/features/drive_mode/domain/drive_mode_repository.dart';

/// [DriveModeRepository] 구현 — `guardDio` 로 `DioException` 을 `Failure`
/// 로 옮긴다(`ManagerRunRepositoryImpl` 과 같은 패턴).
class DriveModeRepositoryImpl implements DriveModeRepository {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(AuthRepositoryImpl 과 같은 이유).
  // ignore: prefer_initializing_formals
  const DriveModeRepositoryImpl({required DriveModeApi api}) : _api = api;

  final DriveModeApi _api;

  @override
  Future<StartRunResult> startRun(String runId) =>
      guardDio(() => _api.startRun(runId));

  @override
  Future<ArriveStopResult> arriveStop({
    required String runId,
    required String stopId,
  }) => guardDio(() => _api.arriveStop(runId: runId, stopId: stopId));
}
