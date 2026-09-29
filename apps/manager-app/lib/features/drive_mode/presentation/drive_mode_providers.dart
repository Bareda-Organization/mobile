import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';

/// [selectedRunIdProvider] 가 가리키는 회차를 [todayRunsProvider] 목록에서
/// 찾는다 — ManagerHome 이 이미 받아 둔 값을 재사용하고, 이 화면 전용의
/// "회차 상세 조회" API 를 새로 만들지 않는다(§4.1 응답이 헤더 표시에
/// 필요한 값을 전부 갖고 있다).
final driveModeRunProvider = Provider<ManagerRun?>((ref) {
  final runId = ref.watch(selectedRunIdProvider);
  final runs = ref.watch(todayRunsProvider).value;
  if (runId == null || runs == null) return null;
  for (final run in runs) {
    if (run.runId == runId) return run;
  }
  return null;
});

/// §4.2 명단 — DriveMode 는 이 목록의 `arrived_at` 로 "다음 도착 처리할
/// 승하차지" 를 계산한다(§4.3 노선 정보 API 는 이번 라운드 범위 밖이라
/// 대신 §4.2 를 재사용, 보고서 § 판단 근거 참고). 기사도 §4.2 조회 권한이
/// 있다(API_SPEC "버스기사(조회)").
final driveModeRosterProvider = FutureProvider<RosterResponse>((ref) {
  final runId = ref.watch(selectedRunIdProvider);
  if (runId == null) {
    throw StateError('선택된 운행이 없습니다');
  }
  return ref.watch(rosterRepositoryProvider).fetchRoster(runId);
});

/// [driveModeRosterProvider] 에서 아직 도착 처리되지 않고 미경유(skipped)
/// 도 아닌 첫 승하차지 — `seq` 순으로 이미 정렬돼 온다(§4.2).
RosterStop? nextUnarrivedStop(RosterResponse roster) {
  for (final stop in roster.stops) {
    if (stop.change == StopChange.skipped) continue;
    if (stop.arrivedAt == null) return stop;
  }
  return null;
}

/// [stop] 뒤에 도착 처리할 승하차지가 더 없으면 `true` — 이 승하차지의 도착 처리가 운행 종료를
/// 일으킨다(C-15). 미경유(skipped)와 이미 도착한 곳은 세지 않는다.
bool isLastRemainingStop(RosterResponse roster, RosterStop stop) {
  final index = roster.stops.indexWhere((s) => s.stopId == stop.stopId);
  for (final later in roster.stops.skip(index + 1)) {
    if (later.change == StopChange.skipped) continue;
    if (later.arrivedAt == null) return false;
  }
  return true;
}
