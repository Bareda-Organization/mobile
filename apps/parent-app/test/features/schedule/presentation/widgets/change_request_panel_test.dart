import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/change_requests/domain/change_request_repository.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/core/runs/domain/run_intent_result.dart';
import 'package:parent_app/core/runs/domain/run_repository.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/features/schedule/presentation/widgets/change_request_panel.dart';

/// 이월 2-2 — API_SPEC §3.8 에러 코드(`CHANGE_WINDOW_CLOSED` ·
/// `CHANGE_LIMIT_REACHED` · `ADDRESS_VERIFICATION_FAILED`)가 이 화면에서
/// 실제로 다른 문구로 갈리는지 확인한다(`run_card_test.dart`의 §8.3 재현과
/// 같은 형태, 대상만 변경 신청 화면).
class _FixedRunRepository implements RunRepository {
  @override
  Future<List<StudentRun>> getRuns(String studentId, {DateTime? date}) async =>
      [_fixtureRun()];

  @override
  Future<RunIntentResult> updateIntent(
    String studentId,
    String runId, {
    required bool riding,
  }) => throw UnimplementedError();
}

class _ThrowingChangeRequestRepository implements ChangeRequestRepository {
  _ThrowingChangeRequestRepository(this.failure);

  final Failure failure;

  @override
  Future<ChangeRequestCreateResult> createChangeRequest(
    String studentId, {
    required ChangeRequestType type,
    required String runId,
    String? newAddress,
    String? reason,
  }) => Future.error(failure);

  @override
  Future<ChangeRequestPage> getChangeRequests(String studentId) async =>
      const ChangeRequestPage(items: [], pendingCount: 0);
}

StudentRun _fixtureRun() => StudentRun(
  runId: 'run-1',
  direction: RunDirection.toAcademy,
  busNo: '1호차',   // 서버가 주는 꼴 — run_card_test 와 같은 이유
  departTime: DateTime(2026, 9, 12, 8),
  runStatus: RunStatus.idle,
  confirmed: false,
  riding: true,
  riderStatus: RiderStatus.waiting,
  stop: const RunStop(stopId: 'stop-1', name: '정문'),
  changeQuotaLeft: 1,
);

Future<void> _pumpAndSubmit(WidgetTester tester, Failure failure) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runRepositoryProvider.overrideWithValue(_FixedRunRepository()),
        changeRequestRepositoryProvider.overrideWithValue(
          _ThrowingChangeRequestRepository(failure),
        ),
      ],
      // 실제 화면(schedule_screen.dart)도 `ListView` 안에 이 패널을 두므로
      // 여기서도 스크롤 가능한 조상을 둔다 — 그렇지 않으면 폼 높이가
      // 테스트 뷰포트를 넘겨 무관한 RenderFlex overflow 로 실패한다.
      child: MaterialApp(
        home: Scaffold(
          body: ListView(
            children: const [ChangeRequestPanel(studentId: 's-1')],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // 회차 선택 → 제출. 라벨 문자열을 직접 적지 않고 위젯이 쓰는 것과
  // 같은 함수(`runOptionLabel`)로 만들어 — 라벨 문구가 바뀌어도 안 깨진다.
  await tester.tap(find.byType(BaraedaSelect).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(runOptionLabel(_fixtureRun())).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('변경 신청하기'));
  await tester.pumpAndSettle();
}

void main() {
  // ⚠ 아래 흐름 시험들은 라벨을 `runOptionLabel` 로 만들어 찾는다 — 편하지만 **그 함수가 틀려도
  // 양쪽이 같이 틀려서 통과한다**(`API_SPEC §8` 에러 사전 대조가 상수를 안 쓰는 것과 같은 이유).
  // 그래서 문구 자체는 여기서 **손으로 적은 리터럴**로 한 번 고정한다.
  test('회차 라벨은 호차를 서버 값 그대로 쓴다 — 단위를 덧붙이지 않는다', () {
    expect(runOptionLabel(_fixtureRun()), '등원 · 1호차');
  });

  testWidgets('신청이 CHANGE_WINDOW_CLOSED 로 실패하면 운행 중 문구를 보여준다', (tester) async {
    await _pumpAndSubmit(
      tester,
      const Failure.api(
        statusCode: 403,
        code: 'CHANGE_WINDOW_CLOSED',
        message: '운행이 시작되어 변경할 수 없습니다',
      ),
    );

    expect(find.text('운행 중에는 신청할 수 없습니다'), findsOneWidget);
  });

  testWidgets('신청이 CHANGE_LIMIT_REACHED 로 실패하면 한도 소진 문구를 보여준다', (tester) async {
    await _pumpAndSubmit(
      tester,
      const Failure.api(
        statusCode: 403,
        code: 'CHANGE_LIMIT_REACHED',
        message: '금일은 변경할 수 없습니다',
      ),
    );

    expect(find.text('이 회차는 변경 가능 횟수를 모두 사용했습니다'), findsOneWidget);
  });

  testWidgets('신청이 ADDRESS_VERIFICATION_FAILED 로 실패하면 주소 재입력 문구를 보여준다', (
    tester,
  ) async {
    await _pumpAndSubmit(
      tester,
      const Failure.api(
        statusCode: 422,
        code: 'ADDRESS_VERIFICATION_FAILED',
        message: '주소를 확인할 수 없습니다',
      ),
    );

    expect(find.text('주소를 확인할 수 없습니다. 다시 입력해 주세요'), findsOneWidget);
  });
}
