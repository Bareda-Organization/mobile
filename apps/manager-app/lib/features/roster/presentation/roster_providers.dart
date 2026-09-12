import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';

/// §4.2 명단 조회 — StopRoster 화면 전용 provider. `drive_mode_providers.dart`
/// 의 `driveModeRosterProvider` 와 같은 엔드포인트를 부르지만 별도로 뒀다 —
/// 두 화면은 새로고침 시점이 다르다(DriveMode 는 도착 처리 직후, StopRoster
/// 는 승하차 처리 직후). 조회 결과 캐시를 공유하는 편이 나을 수 있어
/// 승격 후보로 보고서에 남긴다.
final rosterProvider = FutureProvider<RosterResponse>((ref) {
  final runId = ref.watch(selectedRunIdProvider);
  if (runId == null) {
    throw StateError('선택된 운행이 없습니다');
  }
  return ref.watch(rosterRepositoryProvider).fetchRoster(runId);
});
