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
  busNo: '1호차', // 서버가 주는 꼴 — run_card_test 와 같은 이유
  departTime: DateTime(2026, 9, 12, 8),
  runStatus: RunStatus.idle,
  confirmed: false,
  riding: true,
  riderStatus: RiderStatus.waiting,
  stop: const RunStop(stopId: 'stop-1', name: '정문'),
  changeQuotaLeft: 1,
);

Future<void> _pumpAndSubmit(WidgetTester tester, Failure failure) =>
    _pumpAndSubmitWith(tester, _ThrowingChangeRequestRepository(failure));

/// 접수 성공으로 응답하는 가짜 — 성공 안내 문구 시험용.
class _AcceptingChangeRequestRepository implements ChangeRequestRepository {
  _AcceptingChangeRequestRepository(this.result);

  final ChangeRequestCreateResult result;

  @override
  Future<ChangeRequestCreateResult> createChangeRequest(
    String studentId, {
    required ChangeRequestType type,
    required String runId,
    String? newAddress,
    String? reason,
  }) async => result;

  @override
  Future<ChangeRequestPage> getChangeRequests(String studentId) async =>
      const ChangeRequestPage(items: [], pendingCount: 0);
}

Future<void> _pumpAndSubmitWith(
  WidgetTester tester,
  ChangeRequestRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runRepositoryProvider.overrideWithValue(_FixedRunRepository()),
        changeRequestRepositoryProvider.overrideWithValue(repository),
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

  // R32 P8 — 승인 마감이 `2026-09-12 07:30:00.000` 그대로 나왔다.
  testWidgets('P8 승인 대기 접수 안내의 마감 시각을 한국어 날짜로 보여준다', (tester) async {
    await _pumpAndSubmitWith(
      tester,
      _AcceptingChangeRequestRepository(
        ChangeRequestCreateResult(
          changeRequestId: 'c-1',
          status: ChangeRequestStatus.pending,
          result: 'pending_approval',
          deadlineAt: DateTime(2026, 9, 12, 7, 30),
        ),
      ),
    );

    expect(find.text('승인 대기로 접수됐습니다 (마감 9월 12일 07:30).'), findsOneWidget);
  });

  // R32 P12 — 날짜 선택은 넣지 않았다: 서버가 회차를 그날 하루치만 만들어(DailyRunGenerator)
  // 다른 날짜에는 고를 회차가 없다. 대신 버튼이 왜 눌리지 않는지 말해 준다.
  group('P12 제출할 수 없는 이유 안내', () {
    Future<void> pumpPanel(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runRepositoryProvider.overrideWithValue(_FixedRunRepository()),
            changeRequestRepositoryProvider.overrideWithValue(
              _AcceptingChangeRequestRepository(
                const ChangeRequestCreateResult(
                  changeRequestId: 'c-1',
                  status: ChangeRequestStatus.approved,
                  result: 'applied',
                ),
              ),
            ),
          ],
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
    }

    bool submitEnabled(WidgetTester tester) =>
        tester
            .widget<BaraedaButton>(
              find.widgetWithText(BaraedaButton, '변경 신청하기'),
            )
            .onPressed !=
        null;

    Future<void> chooseRun(WidgetTester tester) async {
      await tester.tap(find.byType(BaraedaSelect).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(runOptionLabel(_fixtureRun())).last);
      await tester.pumpAndSettle();
    }

    testWidgets('회차를 고르기 전에는 버튼이 꺼져 있고 회차를 고르라고 알려 준다', (tester) async {
      await pumpPanel(tester);

      expect(submitEnabled(tester), isFalse);
      expect(find.text('대상 회차를 골라 주세요'), findsOneWidget);
    });

    testWidgets('회차를 고르면 안내가 사라지고 버튼이 켜진다(탑승 취소)', (tester) async {
      await pumpPanel(tester);
      await chooseRun(tester);

      expect(find.text('대상 회차를 골라 주세요'), findsNothing);
      expect(submitEnabled(tester), isTrue);
    });

    testWidgets('승하차지 변경은 주소를 넣을 때까지 버튼이 꺼져 있고 주소를 넣으라고 알려 준다', (
      tester,
    ) async {
      await pumpPanel(tester);
      await chooseRun(tester);
      await tester.tap(find.byType(BaraedaSelect).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('승하차지 변경').last);
      await tester.pumpAndSettle();

      expect(submitEnabled(tester), isFalse);
      expect(find.text('변경할 주소를 입력해 주세요'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '서울시 강남구 3');
      await tester.pumpAndSettle();

      expect(find.text('변경할 주소를 입력해 주세요'), findsNothing);
      expect(submitEnabled(tester), isTrue);
    });
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
