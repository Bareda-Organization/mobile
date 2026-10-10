import 'package:baraeda_core/baraeda_core.dart';
import 'package:manager_app/core/network/guard.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/data/run_summary_store.dart';
import 'package:manager_app/features/home/domain/manager_run_repository.dart';

/// [ManagerRunRepository] 에 기기 저장본을 덧댄다(R52 H2) — 오늘 목록을 받으면
/// 요약을 남기고, 서버에 닿지 못하면(연결 두절 · 5xx) **오늘 저장한** 요약으로
/// 돌아선다. 통신 두절로 앱을 새로 켜도 홈이 회차를 알아 저장 명단 · 비상 신고에
/// 닿는다. 4xx 같은 서버의 판단과 다른 날짜 조회는 저장본으로 덮지 않는다.
class CachedManagerRunRepository implements ManagerRunRepository {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을 쓴다.
  const new({
    required ManagerRunRepository inner,
    required RunSummaryStore store,
    required Clock clock,
    required bool Function() isSignedIn,
  })
    // 위와 같은 이유.
    // ignore: prefer_initializing_formals
    : _inner = inner,
       // 위와 같은 이유.
       // ignore: prefer_initializing_formals
       _store = store,
       // 위와 같은 이유.
       // ignore: prefer_initializing_formals
       _clock = clock,
       // 위와 같은 이유.
       // ignore: prefer_initializing_formals
       _isSignedIn = isSignedIn;

  final ManagerRunRepository _inner;
  final RunSummaryStore _store;
  final Clock _clock;

  /// 로그아웃 뒤에 늦게 도착한 응답을 기기에 남기지 않는다.
  final bool Function() _isSignedIn;

  @override
  Future<List<ManagerRun>> fetchRuns({DateTime? date}) async {
    try {
      final runs = await _inner.fetchRuns(date: date);
      if (date == null && _isSignedIn()) await _store.save(_clock.now(), runs);
      return runs;
    } on Failure catch (failure) {
      if (date != null || !isUnreachableFailure(failure)) rethrow;
      final saved = await _store.read();
      if (saved == null || !_isSameDay(saved.savedAt, _clock.now())) rethrow;
      return saved.runs;
    }
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    final left = a.toLocal();
    final right = b.toLocal();
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}
