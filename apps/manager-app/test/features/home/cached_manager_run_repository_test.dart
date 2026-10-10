import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/home/data/cached_manager_run_repository.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/domain/manager_run_repository.dart';

import '../../support/fake_run_summary_store.dart';
import '../../support/manager_run_fixture.dart';

class _Inner implements ManagerRunRepository {
  new(this.result);

  Object result;

  @override
  Future<List<ManagerRun>> fetchRuns({DateTime? date}) {
    final value = result;
    if (value is Failure) return Future<List<ManagerRun>>.error(value);
    return Future.value(value as List<ManagerRun>);
  }
}

class _FixedClock implements Clock {
  const new(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

/// R52 H2 — 오늘 목록을 받으면 요약을 남기고, 서버에 닿지 못할 때(연결 두절 · 5xx)만 오늘 저장한 요약으로 돌아선다.
void main() {
  final now = DateTime(2026, 10, 10, 10);
  final run = managerRunFixture(departTime: DateTime(2026, 10, 10, 11));

  ({_Inner inner, FakeRunSummaryStore store, CachedManagerRunRepository repo})
  build({
    Object result = const <ManagerRun>[],
    FakeRunSummaryStore? store,
    bool signedIn = true,
  }) {
    final inner = _Inner(result);
    final summary = store ?? FakeRunSummaryStore();
    return (
      inner: inner,
      store: summary,
      repo: CachedManagerRunRepository(
        inner: inner,
        store: summary,
        clock: _FixedClock(now),
        isSignedIn: () => signedIn,
      ),
    );
  }

  test('목록을 받으면 요약을 남긴다', () async {
    final t = build(result: [run]);

    await t.repo.fetchRuns();

    expect(t.store.saved!.runs.single.runId, run.runId);
    expect(t.store.saved!.savedAt, now);
  });

  test('로그아웃 뒤에 늦게 도착한 목록은 남기지 않는다', () async {
    final t = build(result: [run], signedIn: false);

    await t.repo.fetchRuns();

    expect(t.store.saved, isNull);
  });

  test('연결 두절이면 오늘 저장한 요약을 돌려준다', () async {
    final t = build(
      result: const Failure.network(),
      store: FakeRunSummaryStore((savedAt: now, runs: [run])),
    );

    expect((await t.repo.fetchRuns()).single.runId, run.runId);
  });

  test('서버 오류(5xx)여도 오늘 저장한 요약을 돌려준다', () async {
    final t = build(
      result: const Failure.api(statusCode: 503, code: 'X', message: 'm'),
      store: FakeRunSummaryStore((savedAt: now, runs: [run])),
    );

    expect(await t.repo.fetchRuns(), hasLength(1));
  });

  test('서버의 판단(4xx)은 저장 요약으로 덮지 않는다', () async {
    final t = build(
      result: const Failure.api(statusCode: 403, code: 'X', message: 'm'),
      store: FakeRunSummaryStore((savedAt: now, runs: [run])),
    );

    await expectLater(t.repo.fetchRuns(), throwsA(isA<ApiFailure>()));
  });

  test('다른 날짜를 조회할 때는 저장 요약으로 돌아서지 않는다', () async {
    final t = build(
      result: const Failure.network(),
      store: FakeRunSummaryStore((savedAt: now, runs: [run])),
    );

    await expectLater(
      t.repo.fetchRuns(date: DateTime(2026, 10, 11)),
      throwsA(isA<NetworkFailure>()),
    );
  });

  test('요약이 없으면 실패가 그대로 나간다', () async {
    final t = build(result: const Failure.network());

    await expectLater(t.repo.fetchRuns(), throwsA(isA<NetworkFailure>()));
  });

  test('회차 요약은 JSON 왕복으로 같은 값이 된다', () {
    final full = managerRunFixture(
      status: RunStatus.moving,
      roleInRun: UserRole.driver,
      plateNo: '12가3456',
      riderCount: 5,
      absentCount: 1,
      stopCount: 3,
      departTime: DateTime(2026, 10, 10, 11),
    );

    final restored = ManagerRun.fromJson(full.toJson());

    expect(restored.toJson(), full.toJson());
    expect(restored.roleInRun, UserRole.driver);
    expect(restored.departTime, full.departTime);
  });
}
