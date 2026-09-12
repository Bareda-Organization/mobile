import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
import 'package:manager_app/features/drive_mode/data/models/start_run_result.dart';

/// §4.4 운행 시작 · §4.5 승하차지 도착 처리 — 기사 전용(role_policy.dart
/// `canOperateRun`). `presentation` 은 이 인터페이스만 참조한다.
abstract interface class DriveModeRepository {
  Future<StartRunResult> startRun(String runId);

  Future<ArriveStopResult> arriveStop({
    required String runId,
    required String stopId,
  });
}
