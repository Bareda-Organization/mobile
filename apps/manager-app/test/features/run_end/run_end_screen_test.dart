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

  @override
  Future<ReportResult> submitReport({
    required String runId,
    required ReportRequest request,
  }) async {
    lastRunId = runId;
    lastRequest = request;
    return result!;
  }
}

Widget _wrap(Widget child, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
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

  testWidgets('종료 정보가 없으면 안내 문구만 보여준다', (tester) async {
    await tester.pumpWidget(
      _wrap(const RunEndScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        lastArriveResultProvider.overrideWith((ref) => null),
      ]),
    );

    expect(
      find.text('종료 정보가 없습니다 — 운행 모드에서 최종 지점 도착 처리를 마치면 이 화면으로 이동합니다'),
      findsOneWidget,
    );
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
}
