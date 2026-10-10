import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/data/run_summary_store.dart';

/// [RunSummaryStore] 의 메모리 대역 — 시험에는 `flutter_secure_storage` 플랫폼 채널이 없다.
class FakeRunSummaryStore implements RunSummaryStore {
  new([this.saved]);

  ({DateTime savedAt, List<ManagerRun> runs})? saved;

  @override
  Future<({DateTime savedAt, List<ManagerRun> runs})?> read() async => saved;

  @override
  Future<void> save(DateTime savedAt, List<ManagerRun> runs) async =>
      saved = (savedAt: savedAt, runs: runs);

  @override
  Future<void> clear() async => saved = null;
}
