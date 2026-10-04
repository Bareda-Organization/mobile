import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';

/// §4.1 오늘의 담당 회차 목록 — `date` 미전달로 서버 기본값(`today`)을 쓴다.
/// `.autoDispose` 를 쓰지 않는다 — 화면을 떠났다 돌아와도(예: DriveMode →
/// 뒤로가기) 목록을 다시 부르지 않고 유지하는 편이 낫다고 판단(docs/archive/rounds/fe-phases-f2-f5.md
/// §5.2 목표
/// 표에 폴링·자동 새로고침 요건이 없어 수동 `ref.refresh` 만 지원).
final todayRunsProvider = FutureProvider<List<ManagerRun>>((ref) {
  return ref.watch(managerRunRepositoryProvider).fetchRuns();
});

/// 홈이 열려 있는 동안 회차 목록을 다시 받는 주기 — 확정(출발 30분 전)은 서버 배치가 30초 폴링으로
/// 바꾸므로(`ARCHITECTURE §9`) 같은 주기로 따라간다. 더 짧아도 서버 상태가 그보다 빨리 바뀌지 않는다.
const todayRunsRefreshInterval = Duration(seconds: 30);

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

/// 홈 큰 카드에 올릴 회차 — 진행 중 > 확정된 가장 이른 > 없음(시안 `home-escort` 자동 선택).
/// 확정 전 · 이미 끝난 회차는 큰 카드가 되지 않고 "다른 회차" 목록에만 있다.
ManagerRun? pickFeaturedRun(List<ManagerRun> runs) {
  ManagerRun? earliest(bool Function(ManagerRun) test) {
    ManagerRun? picked;
    for (final run in runs) {
      if (!test(run)) continue;
      if (picked == null || run.departTime.isBefore(picked.departTime)) {
        picked = run;
      }
    }
    return picked;
  }

  return earliest((run) => run.runStatus == RunStatus.moving) ??
      earliest((run) => run.confirmed && run.runStatus == RunStatus.confirmed);
}

/// 지금 화면들이 다루는 회차 — 사용자가 목록에서 고른 회차([selectedRunIdProvider])가 아직 유효하면 그것,
/// 아니면 [pickFeaturedRun] 의 자동 선택. 목록을 아직 못 받았으면 `null`.
final focusRunProvider = Provider<ManagerRun?>((ref) {
  final runs = ref.watch(todayRunsProvider).value;
  if (runs == null) return null;
  final selectedId = ref.watch(selectedRunIdProvider);
  for (final run in runs) {
    if (run.runId == selectedId && run.runStatus != RunStatus.finished) {
      return run;
    }
  }
  return pickFeaturedRun(runs);
});
