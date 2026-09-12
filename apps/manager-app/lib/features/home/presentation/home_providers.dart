import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';

/// §4.1 오늘의 담당 회차 목록 — `date` 미전달로 서버 기본값(`today`)을 쓴다.
/// `.autoDispose` 를 쓰지 않는다 — 화면을 떠났다 돌아와도(예: DriveMode →
/// 뒤로가기) 목록을 다시 부르지 않고 유지하는 편이 낫다고 판단(§5.2 목표
/// 표에 폴링·자동 새로고침 요건이 없어 수동 `ref.refresh` 만 지원).
final todayRunsProvider = FutureProvider<List<ManagerRun>>((ref) {
  return ref.watch(managerRunRepositoryProvider).fetchRuns();
});
