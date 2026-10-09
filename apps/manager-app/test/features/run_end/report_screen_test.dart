import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/run_termination_provider.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/position/presentation/position_transmitter.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/run_end/data/models/report_request.dart';
import 'package:manager_app/features/run_end/data/models/report_result.dart';
import 'package:manager_app/features/run_end/domain/reports_repository.dart';
import 'package:manager_app/features/run_end/presentation/report_screen.dart';
import '../../support/manager_run_fixture.dart';

/// 테스트 전용 대역 — 실제 네트워크 대신 호출 여부·인자만 기록한다.
class _FakeReportsRepository implements ReportsRepository {
  new({this.result});

  final ReportResult? result;
  ReportRequest? lastRequest;
  String? lastRunId;
  int callCount = 0;

  @override
  Future<ReportResult> submitReport({
    required String runId,
    required ReportRequest request,
  }) async {
    callCount++;
    lastRunId = runId;
    lastRequest = request;
    return result!;
  }
}

Widget _wrap(
  Widget child,
  List<Override> overrides, {
  Override? roster,
  Override? runs,
  Override? endedRun,
}) {
  return ProviderScope(
    overrides: [
      // R32 M3 — 도착 결과가 없으면 화면이 명단으로 대상 학생을 만든다. 실제 서버로 나가지 않게 막는다.
      roster ??
          rosterProvider.overrideWith(
            (ref) async => const RosterResponse(
              runId: 'run-1',
              busNo: '3호차',
              direction: RunDirection.toAcademy,
              counts: RosterCounts(
                boarded: 0,
                waiting: 0,
                noShow: 0,
                absentN: 0,
              ),
              stops: [],
            ),
          ),
      // 종료 안내는 마지막 도착 처리와 함께 채워지는 회차 표식·회차 목록을 읽는다.
      endedRun ?? transmissionEndedRunIdProvider.overrideWith((ref) => 'run-1'),
      runs ??
          todayRunsProvider.overrideWith(
            (ref) async => [managerRunFixture(status: RunStatus.moving)],
          ),
      ...overrides,
    ],
    child: MaterialApp(home: child),
  );
}

/// 지금 탑승 중인 학생만 담은 명단 — 하차 대기 인원·보고 대상은 이 명단에서 읽는다(F06-14).
Override _boardedRoster(
  List<({String id, String name})> riders, {
  RunDirection direction = RunDirection.toAcademy,
}) => rosterProvider.overrideWith(
      (ref) async => RosterResponse(
        runId: 'run-1',
        busNo: '3호차',
        direction: direction,
        counts: const RosterCounts(
          boarded: 0,
          waiting: 0,
          noShow: 0,
          absentN: 0,
        ),
        stops: [
          RosterStop(
            stopId: 's1',
            seq: 1,
            name: 'A정류장',
            students: [
              for (final rider in riders)
                RosterStudent(
                  riderId: rider.id,
                  studentId: 'st-${rider.id}',
                  name: rider.name,
                  photoUrl: null,
                  guardianPhone: null,
                  canGoAlone: false,
                  status: RiderStatus.boarded,
                ),
            ],
          ),
        ],
      ),
    );

ArriveStopResult _terminationWith({
  required bool finishPending,
  List<RemainingRider> remaining = const [],
}) {
  return ArriveStopResult(
    arrivedAt: DateTime(2026, 9, 12, 8, 30),
    isFinal: true,
    runStatus: RunStatus.moving,
    finishPending: finishPending,
    remaining: remaining,
  );
}

void main() {
  const runId = 'run-1';

  Future<_FakeReportsRepository> pumpReport(
    WidgetTester tester, {
    bool guardianAbsent = false,
    ArriveStopResult? termination,
    Override? roster,
    ReportResult? result,
  }) async {
    final fakeRepo = _FakeReportsRepository(
      result:
          result ??
          ReportResult(
            reportId: 'rep-1',
            reportedAt: DateTime(2026, 9, 12, 8, 31, 5),
          ),
    );
    await tester.pumpWidget(
      _wrap(
        ReportScreen(guardianAbsent: guardianAbsent),
        [
          selectedRunIdProvider.overrideWith((ref) => runId),
          lastArriveResultProvider.overrideWith((ref) => termination),
          reportsRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        roster: roster,
      ),
    );
    await tester.pumpAndSettle();
    return fakeRepo;
  }

  testWidgets('메모 없이 제출하면 안내만 보여주고 보고를 보내지 않는다', (tester) async {
    final fakeRepo = await pumpReport(tester);

    await tester.tap(find.text('보고 제출'));
    await tester.pumpAndSettle();

    expect(find.text('상황 메모를 입력해 주세요'), findsOneWidget);
    expect(fakeRepo.lastRunId, isNull);
  });

  testWidgets('종류를 고르고 메모를 입력해 제출하면 접수 완료 문구를 보여준다', (tester) async {
    final fakeRepo = await pumpReport(tester);

    // 구간 선택은 낱말마다 따로 그려 줄을 바꾼다(`wrapByWord`) — 두 번째 낱말을 누른다.
    await tester.tap(find.text('문제'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '타이어 점검이 필요해요');
    await tester.tap(find.text('보고 제출'));
    await tester.pumpAndSettle();

    expect(fakeRepo.lastRunId, runId);
    expect(fakeRepo.lastRequest?.type, ReportType.vehicleIssue);
    expect(fakeRepo.lastRequest?.memo, '타이어 점검이 필요해요');
    expect(fakeRepo.lastRequest?.riderId, isNull);
    expect(find.text('보고가 접수됐어요'), findsOneWidget);
  });

  testWidgets('보호자 부재는 학생을 고르고 메모를 적어야 제출된다(riderId 를 함께 보낸다)', (tester) async {
    final fakeRepo = await pumpReport(
      tester,
      guardianAbsent: true,
      termination: _terminationWith(
        finishPending: true,
        remaining: const [
          RemainingRider(riderId: 'r1', name: '김바래', stopName: 'A정류장'),
        ],
      ),
      roster: _boardedRoster([(id: 'r1', name: '김바래')]),
    );

    // 학생을 안 고르면 보내지 않는다.
    await tester.enterText(find.byType(TextField), '보호자가 안 나왔어요');
    await tester.tap(find.text('보고 제출'));
    await tester.pumpAndSettle();
    expect(find.text('어느 학생인지 골라 주세요'), findsOneWidget);
    expect(fakeRepo.callCount, 0);

    await tester.tap(find.text('김바래'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('보고 제출'));
    await tester.pumpAndSettle();

    expect(fakeRepo.lastRequest?.type, ReportType.guardianAbsent);
    expect(fakeRepo.lastRequest?.riderId, 'r1');
  });

  testWidgets('보호자 부재 대상은 하차 대기 명단만 보인다', (tester) async {
    await pumpReport(
      tester,
      guardianAbsent: true,
      termination: _terminationWith(
        finishPending: true,
        remaining: const [
          RemainingRider(riderId: 'r1', name: '김바래', stopName: 'A정류장'),
        ],
      ),
      roster: _boardedRoster([(id: 'r1', name: '김바래')]),
    );

    expect(find.byType(BaraedaListRow), findsOneWidget);
    expect(find.widgetWithText(BaraedaListRow, '김바래'), findsOneWidget);
  });

  // H3(UF-E-04 · M-14 · EXC-02) — 동승자의 [예외 보고] 는 이 화면으로 오는데, 보호자 부재는
  // 기사 종료 보류 화면에서만 열렸다. 하원 회차에서는 이 화면에서 보호자 부재를 고를 수 있어야 한다.
  testWidgets('하원 회차의 예외 보고에서 보호자 부재를 골라 학생을 지정해 보고한다', (tester) async {
    final fakeRepo = await pumpReport(
      tester,
      roster: _boardedRoster([
        (id: 'r1', name: '김바래'),
      ], direction: RunDirection.fromAcademy),
    );

    expect(find.text('통제'), findsOneWidget);
    // 구간 선택은 낱말마다 따로 그린다(`wrapByWord`) — 두 번째 낱말을 누른다.
    await tester.tap(find.text('부재'));
    await tester.pumpAndSettle();
    expect(find.text('어느 학생이에요?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '보호자가 안 나왔어요');
    await tester.tap(find.text('김바래'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('보고 제출'));
    await tester.pumpAndSettle();

    expect(fakeRepo.lastRequest?.type, ReportType.guardianAbsent);
    expect(fakeRepo.lastRequest?.riderId, 'r1');
  });

  testWidgets('하원 보호자 부재를 고르고 학생을 안 고르면 보내지 않는다', (tester) async {
    final fakeRepo = await pumpReport(
      tester,
      roster: _boardedRoster([
        (id: 'r1', name: '김바래'),
      ], direction: RunDirection.fromAcademy),
    );

    // 구간 선택은 낱말마다 따로 그린다(`wrapByWord`) — 두 번째 낱말을 누른다.
    await tester.tap(find.text('부재'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '보호자가 안 나왔어요');
    await tester.tap(find.text('보고 제출'));
    await tester.pumpAndSettle();

    expect(find.text('어느 학생인지 골라 주세요'), findsOneWidget);
    expect(fakeRepo.callCount, 0);
  });

  testWidgets('등원 회차에는 보호자 부재 항목이 없다(하원 승하차지의 일)', (tester) async {
    await pumpReport(
      tester,
      roster: _boardedRoster([(id: 'r1', name: '김바래')]),
    );

    expect(find.text('통제'), findsOneWidget);
    expect(find.text('부재'), findsNothing);
  });


  testWidgets('보호자 부재인데 대상 학생이 없으면 이유를 알려 준다', (tester) async {
    await pumpReport(tester, guardianAbsent: true);

    expect(
      find.textContaining('보호자 부재로 보고할 학생이 없어요'),
      findsOneWidget,
    );
    expect(find.byType(BaraedaListRow), findsNothing);
  });

  // R32 M11
  testWidgets('상황 메모가 필수임을 라벨에 밝힌다', (tester) async {
    await pumpReport(tester);

    expect(find.text('상황 메모 (필수)'), findsOneWidget);
  });

  // R46-LAST `Ruling 583` — 이 칸은 퇴원 파기 대상 밖이라 입력 단계에서 개인정보를 줄인다.
  testWidgets('상황 메모 칸 아래에 학생 이름·연락처를 적지 말라고 안내한다', (tester) async {
    await pumpReport(tester);

    expect(find.textContaining('학생 이름·연락처는 적지 마세요'), findsOneWidget);
  });

  testWidgets('접수된 뒤에는 제출 단추가 꺼져 같은 보고가 두 번 나가지 않는다', (tester) async {
    final fakeRepo = await pumpReport(tester);

    await tester.enterText(find.byType(TextField), '도로 공사 중이에요');
    await tester.tap(find.text('보고 제출'));
    await tester.pumpAndSettle();
    expect(fakeRepo.callCount, 1);

    final button = tester.widget<BaraedaButton>(
      find.widgetWithText(BaraedaButton, '보고 제출'),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.text('보고 제출'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(fakeRepo.callCount, 1);
  });

  // N-08 — 현장 예외 보고 memo 는 200자까지다(API_SPEC 자유 입력 메모 상한, 넘으면 422).
  testWidgets('메모 입력칸은 200자에서 멈춘다', (tester) async {
    await pumpReport(tester);

    await tester.enterText(find.byType(TextField), '가' * 250);

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text.length,
      200,
    );
  });
}
