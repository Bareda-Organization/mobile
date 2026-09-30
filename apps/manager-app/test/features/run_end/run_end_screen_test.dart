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
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/run_end/data/models/report_request.dart';
import 'package:manager_app/features/run_end/data/models/report_result.dart';
import 'package:manager_app/features/run_end/domain/reports_repository.dart';
import 'package:manager_app/features/run_end/presentation/run_end_screen.dart';

/// 테스트 전용 대역 — 실제 네트워크 대신 호출 여부·인자만 기록한다.
class _FakeReportsRepository implements ReportsRepository {
  _FakeReportsRepository({this.result});

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

Widget _wrap(Widget child, List<Override> overrides) {
  return ProviderScope(
    overrides: [
      // R32 M3 — 도착 결과가 없으면 화면이 명단으로 대상 학생을 만든다. 실제 서버로 나가지 않게 막는다.
      rosterProvider.overrideWith(
        (ref) async => const RosterResponse(
          runId: 'run-1',
          busNo: '3호차',
          direction: RunDirection.toAcademy,
          counts: RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
          stops: [],
        ),
      ),
      ...overrides,
    ],
    child: MaterialApp(home: child),
  );
}

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

  testWidgets('종료 정보가 없으면 종료 안내 없이 예외 보고 화면으로 그린다(R32 M3)', (tester) async {
    await tester.pumpWidget(
      _wrap(const RunEndScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        lastArriveResultProvider.overrideWith((ref) => null),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('종료 정보가 없습니다'), findsNothing);
    expect(find.text('예외 보고'), findsOneWidget);
    expect(find.text('보고 제출'), findsOneWidget);
  });

  testWidgets('하차 대기 인원이 있으면 남은 인원 수를 보여준다', (tester) async {
    await tester.pumpWidget(
      _wrap(const RunEndScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        lastArriveResultProvider.overrideWith(
          (ref) => _terminationWith(
            finishPending: true,
            remaining: const [
              RemainingRider(riderId: 'r1', name: '김바래', stopName: 'A정류장'),
              RemainingRider(riderId: 'r2', name: '이다솜', stopName: 'B정류장'),
            ],
          ),
        ),
      ]),
    );

    expect(
      find.textContaining('하차 대기 2명 남음(전원 하차해야 운행이 종료됩니다)'),
      findsOneWidget,
    );
  });

  testWidgets('메모 없이 제출하면 안내만 보여주고 보고를 보내지 않는다', (tester) async {
    final fakeRepo = _FakeReportsRepository();

    await tester.pumpWidget(
      _wrap(const RunEndScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        lastArriveResultProvider.overrideWith((ref) => null),
        reportsRepositoryProvider.overrideWithValue(fakeRepo),
      ]),
    );

    await tester.tap(find.text('보고 제출'));
    await tester.pumpAndSettle();

    expect(find.text('상황 메모를 입력해 주세요'), findsOneWidget);
    expect(fakeRepo.lastRunId, isNull);
  });

  testWidgets('메모를 입력하고 제출하면 접수 완료 문구를 보여준다', (tester) async {
    final fakeRepo = _FakeReportsRepository(
      result: ReportResult(
        reportId: 'rep-1',
        reportedAt: DateTime(2026, 9, 12, 8, 31, 5),
      ),
    );

    await tester.pumpWidget(
      _wrap(const RunEndScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        lastArriveResultProvider.overrideWith((ref) => null),
        reportsRepositoryProvider.overrideWithValue(fakeRepo),
      ]),
    );

    await tester.enterText(find.byType(TextField), '보호자가 안 나왔습니다');
    await tester.tap(find.text('보고 제출'));
    await tester.pumpAndSettle();

    expect(fakeRepo.lastRunId, runId);
    expect(fakeRepo.lastRequest?.type, ReportType.guardianAbsent);
    expect(fakeRepo.lastRequest?.memo, '보호자가 안 나왔습니다');
    expect(find.textContaining('보고가 접수됐습니다'), findsOneWidget);
  });

  testWidgets('대상 학생 선택은 하차 대기 명단([remaining])만 옵션으로 보여준다', (tester) async {
    await tester.pumpWidget(
      _wrap(const RunEndScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        lastArriveResultProvider.overrideWith(
          (ref) => _terminationWith(
            finishPending: true,
            remaining: const [
              RemainingRider(riderId: 'r1', name: '김바래', stopName: 'A정류장'),
            ],
          ),
        ),
      ]),
    );

    final select = tester.widget<BaraedaSelect>(find.byType(BaraedaSelect));
    expect(select.enabled, isTrue);
    expect(select.options.map((option) => option.value), ['r1']);
    expect(select.options.map((option) => option.label), ['김바래']);
  });

  testWidgets('하차 대기 명단이 비어 있으면 대상 학생 선택을 비활성화한다', (tester) async {
    await tester.pumpWidget(
      _wrap(const RunEndScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        lastArriveResultProvider.overrideWith((ref) => null),
      ]),
    );

    final select = tester.widget<BaraedaSelect>(find.byType(BaraedaSelect));
    expect(select.enabled, isFalse);
    expect(select.options, isEmpty);
  });

  // R32 M11
  testWidgets('상황 메모가 필수임을 라벨에 밝힌다', (tester) async {
    await tester.pumpWidget(
      _wrap(const RunEndScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        lastArriveResultProvider.overrideWith((ref) => null),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('상황 메모 (필수)'), findsOneWidget);
  });

  testWidgets('보호자 부재인데 대상 학생이 없으면 이유를 알려 준다', (tester) async {
    await tester.pumpWidget(
      _wrap(const RunEndScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        lastArriveResultProvider.overrideWith((ref) => null),
      ]),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('보호자 부재로 보고할 학생이 없습니다 — 혼자 귀가할 수 없는 학생이 탑승 중일 때만 고를 수 있습니다'),
      findsOneWidget,
    );
  });

  testWidgets('대상 학생이 있으면 빈 목록 안내는 없다', (tester) async {
    await tester.pumpWidget(
      _wrap(const RunEndScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        lastArriveResultProvider.overrideWith(
          (ref) => _terminationWith(
            finishPending: true,
            remaining: const [
              RemainingRider(riderId: 'r1', name: '김바래', stopName: 'A정류장'),
            ],
          ),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('보고할 학생이 없습니다'), findsNothing);
  });

  testWidgets('접수된 뒤에는 제출 버튼이 꺼져 같은 보고가 두 번 나가지 않는다', (tester) async {
    final fakeRepo = _FakeReportsRepository(
      result: ReportResult(
        reportId: 'rep-1',
        reportedAt: DateTime(2026, 9, 12, 8, 31, 5),
      ),
    );
    await tester.pumpWidget(
      _wrap(const RunEndScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        lastArriveResultProvider.overrideWith((ref) => null),
        reportsRepositoryProvider.overrideWithValue(fakeRepo),
      ]),
    );

    await tester.enterText(find.byType(TextField), '보호자가 안 나왔습니다');
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
    await tester.pumpWidget(
      _wrap(const RunEndScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        lastArriveResultProvider.overrideWith((ref) => null),
        reportsRepositoryProvider.overrideWithValue(
          _FakeReportsRepository(
            result: ReportResult(
              reportId: 'rep-1',
              reportedAt: DateTime(2026, 9, 12, 8, 31, 5),
            ),
          ),
        ),
      ]),
    );

    await tester.enterText(find.byType(TextField), '가' * 250);

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text.length,
      200,
    );
  });
}
