import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';

/// §4.1 오늘의 담당 회차 목록 — `date` 미전달로 서버 기본값(`today`)을 쓴다.
/// `.autoDispose` 를 쓰지 않는다 — 화면을 떠났다 돌아와도(예: DriveMode →
/// 뒤로가기) 목록을 다시 부르지 않고 유지하는 편이 낫다고 판단(§5.2 목표
/// 표에 폴링·자동 새로고침 요건이 없어 수동 `ref.refresh` 만 지원).
final todayRunsProvider = FutureProvider<List<ManagerRun>>((ref) {
  return ref.watch(managerRunRepositoryProvider).fetchRuns();
});

/// 앱을 다시 켠 뒤 위치 송신을 이어 갈 회차 — 운행 중(`moving`)이고 내가 기사로 배치된 회차.
/// 여럿이면 출발 시각이 가장 늦은 것(가장 최근에 출발한 운행). 없으면 `null`.
ManagerRun? pickResumableRun(List<ManagerRun> runs) {
  ManagerRun? picked;
  for (final run in runs) {
    if (run.runStatus != RunStatus.moving) continue;
    if (run.roleInRun != UserRole.driver) continue;
    if (picked == null || run.departTime.isAfter(picked.departTime)) {
      picked = run;
    }
  }
  return picked;
}
