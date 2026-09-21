import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  _ThrowingRunRepository(this.failure);

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
  riding: true,
  riderStatus: status,
  stop: const RunStop(stopId: 'stop-1', name: '정문'),
  changeQuotaLeft: 1,
);

Future<void> _pumpWith(WidgetTester tester, RunRepository repository) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [runRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        home: Scaffold(
          body: RunCard(studentId: 's-1', run: _fixtureRun(), canToggle: true),
        ),
      ),
    ),
  );
  await tester.tap(find.byType(BaraedaSwitch));
  await tester.pumpAndSettle();
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

  testWidgets('토글이 CHANGE_WINDOW_CLOSED 로 실패하면 운행 중 문구를 보여준다', (
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

    expect(find.text('운행 중에는 이 변경을 되돌릴 수 없습니다'), findsOneWidget);
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
}
