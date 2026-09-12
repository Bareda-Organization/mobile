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

StudentRun _fixtureRun() => StudentRun(
  runId: 'run-1',
  direction: RunDirection.toAcademy,
  busNo: '1',
  departTime: DateTime(2026, 9, 12, 8),
  runStatus: RunStatus.idle,
  confirmed: false,
  riding: true,
  riderStatus: RiderStatus.waiting,
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
