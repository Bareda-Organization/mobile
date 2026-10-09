import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
import 'package:manager_app/features/drive_mode/data/models/start_run_result.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';

/// §4.4 운행 시작 · §4.5 승하차지 도착 처리 — 기사 전용(role_policy.dart
/// `canOperateRun`). `presentation` 은 이 인터페이스만 참조한다.
abstract interface class DriveModeRepository {
  Future<StartRunResult> startRun(String runId);

  /// 승하차지 도착 처리. 서버에 닿지 못하면(또는 서버가 5xx) 오프라인 큐에 쌓고
  /// [Queued] 를 돌려준다(`USER_FLOWS §12.2` · UF-D-04 · M-06, `Ruling 859`).
  /// 재전송이 이미 처리된 도착이면(`DUPLICATE_ARRIVE`) 큐가 성공으로 흡수한다.
  Future<SendOutcome<ArriveStopResult>> arriveStop({
    required String runId,
    required String stopId,
  });
}
