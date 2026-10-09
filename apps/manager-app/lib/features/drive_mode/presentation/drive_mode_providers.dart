import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';
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

/// 도착 처리가 오프라인 큐에 저장돼 서버 반영만 기다리는 승하차지 id(`Ruling 859`) — 영구 실패 행은 뺀다(서버에
/// 닿지 못한 채 포기된 도착이라 다시 눌러야 한다). 운행 화면이 이 곳들을 "도착 처리함"으로 보고 다음 곳을 가리킨다.
final queuedArrivalStopIdsProvider = Provider<Set<String>>((ref) {
  final pending = ref.watch(pendingRequestsProvider).value ?? const [];
  return {
    for (final request in pending)
      if (!request.failed) ?request.arriveStopId,
  };
});

/// [driveModeRosterProvider] 에서 아직 도착 처리되지 않고 미경유(skipped)
/// 도 아닌 첫 승하차지 — `seq` 순으로 이미 정렬돼 온다(§4.2). [queuedStopIds] 는 큐에 저장돼 반영을 기다리는
/// 도착이라 이미 처리한 곳으로 본다.
RosterStop? nextUnarrivedStop(
  RosterResponse roster, {
  Set<String> queuedStopIds = const {},
}) {
  for (final stop in roster.stops) {
    if (stop.change == StopChange.skipped) continue;
    if (stop.arrivedAt == null && !queuedStopIds.contains(stop.stopId)) {
      return stop;
    }
  }
  return null;
}

/// [stop] 뒤에 도착 처리할 승하차지가 더 없으면 `true` — 이 승하차지의 도착 처리가 운행 종료를
/// 일으킨다(C-15). 미경유(skipped)와 이미 도착한 곳·큐에 저장된 곳은 세지 않는다.
bool isLastRemainingStop(
  RosterResponse roster,
  RosterStop stop, {
  Set<String> queuedStopIds = const {},
}) {
  final index = roster.stops.indexWhere((s) => s.stopId == stop.stopId);
  for (final later in roster.stops.skip(index + 1)) {
    if (later.change == StopChange.skipped) continue;
    if (later.arrivedAt == null && !queuedStopIds.contains(later.stopId)) {
      return false;
    }
  }
  return true;
}
