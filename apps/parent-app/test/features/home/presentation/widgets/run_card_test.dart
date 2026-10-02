import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/core/runs/domain/run_intent_result.dart';
import 'package:parent_app/core/runs/domain/run_repository.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/features/home/presentation/widgets/run_card.dart';

/// API_SPEC §8.3 에러 코드(`CHANGE_LIMIT_REACHED`·`CHANGE_WINDOW_CLOSED`)가
/// §3.6 토글 실패 시 화면에 실제로 다른 문구로 갈리는지 확인한다
/// (R1 목표 5 — "그 화면에 걸리는 에러 코드를 실제로 재현").
class _ThrowingRunRepository implements RunRepository {
  new(this.failure);

  final Failure failure;

  @override
  Future<List<StudentRun>> getRuns(String studentId, {DateTime? date}) =>
      throw UnimplementedError();

  @override
  Future<RunIntentResult> updateIntent(
    String studentId,
    String runId, {
    required bool riding,
  }) => Future.error(failure);
}

StudentRun _fixtureRun({
  RiderStatus status = RiderStatus.waiting,
  DateTime? departTime,
  bool riding = true,
}) => StudentRun(
  runId: 'run-1',
  direction: RunDirection.toAcademy,
  // ⚠ 서버가 주는 값은 **호차 이름 그 자체**다(`ERD bus.bus_no varchar(20)` · 시드 '1호차'·'2호차'
  // · `API_SPEC` "호차"). 맨 숫자 '1' 로 두면 화면이 단위를 덧붙여도 시험이 못 잡는다 —
  // 실제로 2026-09-20 까지 "1호차번" 이 그렇게 살아남았다.
  busNo: '1호차',
  departTime: departTime ?? DateTime(2026, 9, 12, 8),
  runStatus: RunStatus.idle,
  confirmed: false,
  riding: riding,
  riderStatus: status,
  stop: const RunStop(stopId: 'stop-1', name: '정문'),
  changeQuotaLeft: 1,
);

Future<void> _pumpWith(
  WidgetTester tester,
  RunRepository repository, {
  bool riding = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [runRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        home: Scaffold(
          body: RunCard(
            studentId: 's-1',
            run: _fixtureRun(riding: riding),
            canToggle: true,
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byType(BaraedaSwitch));
  await tester.pumpAndSettle();
  // R32 P4 — 끄기는 확인 창을 거친다. 실패 문구 시험은 확인까지 눌러 요청을 보낸다.
  if (find.text('탑승 취소').evaluate().isNotEmpty) {
    await tester.tap(find.text('탑승 취소'));
    await tester.pumpAndSettle();
  }
}

void main() {
  /// `absent`(미등원)와 `no_show`(미승차)는 **반드시 구분**한다 — `FEATURE_SPEC C-02`.
  ///
  /// ⚠ 학부모에게 이 둘은 전혀 다른 일이다. `absent` 는 **내가 직접 껐다**(정상),
  /// `no_show` 는 **버스가 왔는데 아이가 안 나왔다**(사고). 한 라벨로 합치면
  /// 학부모가 사고를 못 알아챈다. 색도 사양이 가른다 — 미등원 스톤 · 미승차 레드.
  Future<void> pumpWithStatus(WidgetTester tester, RiderStatus status) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: RunCard(
              studentId: 's-1',
              run: _fixtureRun(status: status),
              canToggle: false,
            ),
          ),
        ),
      ),
    );
  }

  // ⚠ 2026-09-21 실측 — 서버가 주는 시각은 **UTC 순간**(`2026-09-21T10:40:19Z`)인데
  // 화면이 그 값의 `hour`·`minute` 를 그대로 읽어 **9시간 어긋난 시각**을 보여줬다
  // (19:40 출발을 "10:40 출발" 로). `DateTime.parse` 는 오프셋이 붙은 문자열을
  // 언제나 **UTC DateTime** 으로 돌려주므로, 벽시계로 쓰려면 `toLocal()` 이 필요하다.
  //
  // 기대값을 `toLocal()` 로 계산하는 이유 — 시험기의 표준시를 코드에서 바꿀 수단이
  // 부재하다. 표준시가 UTC 인 기계에서는 이 단언이 참으로 통과하지만(변환 여부와
  // 무관), **KST 에서 돌리면 변환이 빠진 순간 실패한다.**
  testWidgets('출발 시각을 기기 표준시로 보여준다 — 서버가 준 UTC 그대로가 아니라', (tester) async {
    final departUtc = DateTime.utc(2026, 9, 21, 10, 40);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: RunCard(
              studentId: 's-1',
              run: _fixtureRun(departTime: departUtc),
              canToggle: false,
            ),
          ),
        ),
      ),
    );

    final local = departUtc.toLocal();
    final expected =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    expect(find.textContaining('$expected 출발'), findsOneWidget);
  });

  testWidgets('미등원과 미승차를 다른 말로 보여준다', (tester) async {
    await pumpWithStatus(tester, RiderStatus.absent);
    expect(find.text('미등원'), findsOneWidget);
    expect(find.text('미승차'), findsNothing);

    await pumpWithStatus(tester, RiderStatus.noShow);
    expect(find.text('미승차'), findsOneWidget);
    expect(find.text('미등원'), findsNothing);
  });

  testWidgets('호차를 서버 값 그대로 보여준다 — 단위를 덧붙이지 않는다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: RunCard(
              studentId: 's-1',
              run: _fixtureRun(),
              canToggle: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('등원 · 1호차'), findsOneWidget);
    expect(
      find.text('등원 · 1호차번'),
      findsNothing,
      reason: '`bus_no` 가 이미 "1호차" 라 "번" 을 붙이면 "1호차번" 이 된다',
    );
  });

  // F05-14 — 연결이 끊긴 것과 서버가 거절한 것은 학부모가 다르게 대응한다(다시 눌러 보기 vs 학원 문의).
  testWidgets('F05-14 토글이 네트워크 오류로 실패하면 네트워크 확인 문구를 보여준다', (tester) async {
    await _pumpWith(tester, _ThrowingRunRepository(const Failure.network()));

    expect(find.text('네트워크 상태를 확인해 주세요'), findsOneWidget);
    expect(find.text('변경을 처리하지 못했습니다'), findsNothing);
  });

  // N-02 · Ruling 376 — 임시 취소된 회차의 탑승 토글은 409 RUN_CANCELED.
  testWidgets('N-02 토글이 RUN_CANCELED 로 실패하면 임시 취소 문구를 보여준다', (tester) async {
    await _pumpWith(
      tester,
      _ThrowingRunRepository(
        const Failure.api(
          statusCode: 409,
          code: 'RUN_CANCELED',
          message: '취소된 회차입니다',
        ),
      ),
    );

    expect(find.text('학원에서 임시로 취소한 회차입니다. 학원에 문의해 주세요'), findsOneWidget);
  });

  testWidgets('토글이 CHANGE_LIMIT_REACHED 로 실패하면 한도 소진 문구를 보여준다', (
    tester,
  ) async {
    await _pumpWith(
      tester,
      _ThrowingRunRepository(
        const Failure.api(
          statusCode: 403,
          code: 'CHANGE_LIMIT_REACHED',
          message: '금일은 변경할 수 없습니다',
        ),
      ),
    );

    expect(find.text('이 회차는 변경 가능 횟수를 모두 사용했습니다'), findsOneWidget);
  });

  // Ruling 334 · BR-029 — 같은 CHANGE_WINDOW_CLOSED 가 끄기(이미 승하차 처리된 학생)와
  // 켜기(출발 30분 전부터 탑승 복귀 불가)에서 뜻이 다르다. 한 문구로 합치면 끄기 실패에
  // "되돌릴 수 없습니다" 가 떠 학부모가 무엇이 막혔는지 알 수 없다.
  testWidgets('끄기가 CHANGE_WINDOW_CLOSED 로 실패하면 이미 처리됨 문구를 보여준다', (
    tester,
  ) async {
    await _pumpWith(
      tester,
      _ThrowingRunRepository(
        const Failure.api(
          statusCode: 403,
          code: 'CHANGE_WINDOW_CLOSED',
          message: '운행이 시작되어 변경할 수 없습니다',
        ),
      ),
    );

    expect(
      find.text('이미 탑승 처리가 진행돼 앱에서는 바꿀 수 없습니다. 학원에 문의해 주세요'),
      findsOneWidget,
    );
  });

  testWidgets('켜기가 CHANGE_WINDOW_CLOSED 로 실패하면 탑승 복귀 불가 문구를 보여준다', (
    tester,
  ) async {
    await _pumpWith(
      tester,
      _ThrowingRunRepository(
        const Failure.api(
          statusCode: 403,
          code: 'CHANGE_WINDOW_CLOSED',
          message: '운행이 시작되어 변경할 수 없습니다',
        ),
      ),
      riding: false,
    );

    expect(find.text('출발 30분 전부터는 탑승으로 되돌릴 수 없습니다'), findsOneWidget);
  });

  testWidgets('canToggle 이 false 면 등원 여부 토글 스위치 자체가 렌더링되지 않는다', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runRepositoryProvider.overrideWithValue(
            _ThrowingRunRepository(
              const Failure.api(
                statusCode: 500,
                code: 'UNUSED',
                message: '사용되지 않음 — 이 테스트는 토글을 누르지 않는다',
              ),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: RunCard(
              studentId: 's-1',
              run: _fixtureRun(),
              canToggle: false,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BaraedaSwitch), findsNothing);
    expect(find.text('오늘 탑승'), findsNothing);
  });

  // ---- R32 P4 — 확인 창 · 스위치 줄의 지도 이동 제외 · 확정까지 남은 시간 ----

  /// 호출을 기록하는 가짜 저장소 — 취소하면 요청이 나가지 않는다는 시험에 쓴다.
  Future<_RecordingRunRepository> pumpRecording(
    WidgetTester tester, {
    bool riding = true,
    RunStatus runStatus = RunStatus.idle,
    bool confirmed = false,
    DateTime? departTime,
    DateTime? now,
    List<String>? pushed,
    _RecordingRunRepository? recording,
  }) async {
    final repository = recording ?? _RecordingRunRepository();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: RunCard(
              studentId: 's-1',
              run: _fixtureRun(
                riding: riding,
                departTime: departTime,
              ).copyForTest(runStatus: runStatus, confirmed: confirmed),
              canToggle: true,
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.liveMap,
          builder: (_, _) {
            pushed?.add(AppRoutes.liveMap);
            return const Scaffold(body: Text('지도 화면'));
          },
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runRepositoryProvider.overrideWithValue(repository),
          if (now != null) clockProvider.overrideWithValue(_FixedClock(now)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    return repository;
  }

  testWidgets('P4 끄려고 스위치를 누르면 확인 창이 뜨고 취소하면 요청이 나가지 않는다', (tester) async {
    final repository = await pumpRecording(tester);

    await tester.tap(find.byType(BaraedaSwitch));
    await tester.pumpAndSettle();
    expect(find.text('탑승 취소'), findsOneWidget);

    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();

    expect(repository.calls, isEmpty);
  });

  testWidgets('P4 확인 창에서 [탑승 취소] 를 누르면 그때 요청이 나간다', (tester) async {
    final repository = await pumpRecording(tester);

    await tester.tap(find.byType(BaraedaSwitch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('탑승 취소'));
    await tester.pumpAndSettle();

    expect(repository.calls, [false]);
  });

  testWidgets('P4 켜기는 확인 창 없이 바로 요청이 나간다', (tester) async {
    final repository = await pumpRecording(tester, riding: false);

    await tester.tap(find.byType(BaraedaSwitch));
    await tester.pumpAndSettle();

    expect(find.text('탑승 취소'), findsNothing);
    expect(repository.calls, [true]);
  });

  testWidgets('P4 확정 전(①구간) 확인 문구는 즉시 반영을 알린다', (tester) async {
    await pumpRecording(tester);

    await tester.tap(find.byType(BaraedaSwitch));
    await tester.pumpAndSettle();

    expect(find.textContaining('바로 반영'), findsOneWidget);
    expect(find.textContaining('승인'), findsNothing);
  });

  testWidgets('P4 확정 뒤(②구간) 확인 문구는 승인 요청과 회차당 1회를 알린다', (tester) async {
    await pumpRecording(
      tester,
      runStatus: RunStatus.confirmed,
      confirmed: true,
    );

    await tester.tap(find.byType(BaraedaSwitch));
    await tester.pumpAndSettle();

    expect(find.textContaining('승인'), findsOneWidget);
    expect(find.textContaining('1번'), findsOneWidget);
    expect(find.textContaining('바로 반영'), findsNothing);
  });

  testWidgets('P4 스위치 줄을 눌러도 지도 화면으로 이동하지 않는다 — 카드 윗부분은 이동한다', (
    tester,
  ) async {
    final pushed = <String>[];
    await pumpRecording(tester, pushed: pushed);

    await tester.tap(find.byType(BaraedaSwitch));
    await tester.pumpAndSettle();
    expect(pushed, isEmpty);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('등원 · 1호차'));
    await tester.pumpAndSettle();
    expect(pushed, [AppRoutes.liveMap]);
  });

  // 전송 중에는 스위치가 비활성이 되어 눌림이 바깥 카드로 새면 지도 화면이 열렸다.
  testWidgets('P4 전송 중에 스위치 줄을 눌러도 지도 화면이 열리지 않는다', (tester) async {
    final pushed = <String>[];
    final pending = Completer<RunIntentResult>();
    await pumpRecording(
      tester,
      riding: false,
      pushed: pushed,
      recording: _RecordingRunRepository(pending: pending),
    );

    await tester.tap(find.byType(BaraedaSwitch));
    await tester.pump();
    await tester.tap(find.byType(BaraedaSwitch));
    await tester.pump();

    expect(pushed, isEmpty);
    pending.complete(
      const RunIntentResult(
        result: RunIntentApplyResult.applied,
        riding: true,
        riderStatus: RiderStatus.waiting,
        changeQuotaLeft: 1,
      ),
    );
    await tester.pumpAndSettle();
  });

  // R32 P8 — 승인 마감이 `2026-09-12 07:30:00.000` 그대로 나왔다. 승인 주체도 사양(UF-P-05)
  // 대로 학원 관리자다.
  testWidgets('P8 승인 대기 안내의 마감 시각을 한국어 날짜로 보여준다', (tester) async {
    await pumpRecording(
      tester,
      runStatus: RunStatus.confirmed,
      confirmed: true,
      recording: _RecordingRunRepository(
        result: RunIntentResult(
          result: RunIntentApplyResult.pendingApproval,
          riding: true,
          riderStatus: RiderStatus.waiting,
          changeQuotaLeft: 0,
          deadlineAt: DateTime(2026, 9, 12, 7, 30),
        ),
      ),
    );

    await tester.tap(find.byType(BaraedaSwitch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('탑승 취소'));
    await tester.pumpAndSettle();

    expect(
      find.text('학원 관리자 승인 대기 중입니다 (마감 9월 12일 07:30).'),
      findsOneWidget,
    );
  });

  testWidgets('P4 확정 전이면 확정까지 남은 시간을 보여준다', (tester) async {
    // 출발 08:00 → 확정은 07:30. 지금 06:10 이면 1시간 20분 남았다.
    await pumpRecording(
      tester,
      departTime: DateTime(2026, 9, 12, 8),
      now: DateTime(2026, 9, 12, 6, 10),
    );

    expect(find.text('확정까지 1시간 20분'), findsOneWidget);
  });

  testWidgets('P4 확정된 회차에는 남은 시간을 보여주지 않는다', (tester) async {
    await pumpRecording(
      tester,
      runStatus: RunStatus.confirmed,
      confirmed: true,
      departTime: DateTime(2026, 9, 12, 8),
      now: DateTime(2026, 9, 12, 7, 40),
    );

    expect(find.textContaining('확정까지'), findsNothing);
  });
}

class _FixedClock implements Clock {
  const new(this._value);

  final DateTime _value;

  @override
  DateTime now() => _value;
}

/// 호출된 `riding` 값을 순서대로 기록한다.
class _RecordingRunRepository implements RunRepository {
  new({this.pending, this.result});

  /// 주어지면 `updateIntent` 가 이 결과를 돌려준다.
  final RunIntentResult? result;

  final calls = <bool>[];

  /// 주어지면 이 값이 완료될 때까지 응답을 미룬다.
  final Completer<RunIntentResult>? pending;

  @override
  Future<List<StudentRun>> getRuns(String studentId, {DateTime? date}) async =>
      const [];

  @override
  Future<RunIntentResult> updateIntent(
    String studentId,
    String runId, {
    required bool riding,
  }) async {
    calls.add(riding);
    if (pending != null) return await pending!.future;
    if (result != null) return result!;
    return RunIntentResult(
      result: RunIntentApplyResult.applied,
      riding: riding,
      riderStatus: RiderStatus.waiting,
      changeQuotaLeft: 1,
    );
  }
}

extension on StudentRun {
  /// 시험용 — 구간 판정에 쓰는 두 값만 바꾼 사본.
  StudentRun copyForTest({RunStatus? runStatus, bool? confirmed}) => StudentRun(
    runId: runId,
    direction: direction,
    busNo: busNo,
    departTime: departTime,
    runStatus: runStatus ?? this.runStatus,
    confirmed: confirmed ?? this.confirmed,
    riding: riding,
    riderStatus: riderStatus,
    stop: stop,
    changeQuotaLeft: changeQuotaLeft,
  );
}
