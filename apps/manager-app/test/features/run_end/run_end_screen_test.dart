import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/run_termination_provider.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/position/presentation/position_transmitter.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/run_end/presentation/run_end_screen.dart';

import '../../support/manager_run_fixture.dart';

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
Override _boardedRoster(List<({String id, String name})> riders) =>
    rosterProvider.overrideWith(
      (ref) async => RosterResponse(
        runId: 'run-1',
        busNo: '3호차',
        direction: RunDirection.toAcademy,
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

/// 운행이 끝난 명단 — 서버 `counts.boarded` 는 **지금 탑승 중인** 학생 수라 전원이 하차한 종료 뒤에는 0 이다
/// (`RosterQueryService.countsOf`). 하차 학생은 `stops[].students[].status == alighted` 행으로만 보인다.
RosterResponse _finishedResponse({
  required int alighted,
  int noShow = 0,
  int absentN = 0,
}) => RosterResponse(
  runId: 'run-1',
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  counts: RosterCounts(
    boarded: 0,
    waiting: 0,
    noShow: noShow,
    absentN: absentN,
  ),
  stops: [
    RosterStop(
      stopId: 's1',
      seq: 1,
      name: 'A정류장',
      students: [
        // 하차 학생을 두 정류장에 나눠 담는다 — 합계는 정류장을 가리지 않는다.
        for (var i = 0; i < alighted; i++)
          if (i.isEven)
            RosterStudent(
              riderId: 'r$i',
              studentId: 'st-$i',
              name: '학생$i',
              photoUrl: null,
              guardianPhone: null,
              canGoAlone: false,
              status: RiderStatus.alighted,
            ),
      ],
    ),
    RosterStop(
      stopId: 's2',
      seq: 2,
      name: 'B정류장',
      students: [
        for (var i = 0; i < alighted; i++)
          if (i.isOdd)
            RosterStudent(
              riderId: 'r$i',
              studentId: 'st-$i',
              name: '학생$i',
              photoUrl: null,
              guardianPhone: null,
              canGoAlone: false,
              status: RiderStatus.alighted,
            ),
        for (var i = 0; i < noShow; i++)
          RosterStudent(
            riderId: 'n$i',
            studentId: 'st-n$i',
            name: '미승차$i',
            photoUrl: null,
            guardianPhone: null,
            canGoAlone: false,
            status: RiderStatus.noShow,
          ),
      ],
    ),
  ],
);

Override _finishedRoster({
  required int alighted,
  int noShow = 0,
  int absentN = 0,
}) => rosterProvider.overrideWith(
  (ref) async =>
      _finishedResponse(alighted: alighted, noShow: noShow, absentN: absentN),
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

  testWidgets('종료 정보가 없으면 끝난 운행이 없다고 안내한다', (tester) async {
    await tester.pumpWidget(
      _wrap(const RunEndScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        lastArriveResultProvider.overrideWith((ref) => null),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('끝난 운행이 없어요'), findsOneWidget);
  });

  testWidgets('하차 대기 인원이 있으면 종료가 보류됐다고 알리고 남은 인원 수를 보여준다', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RunEndScreen(),
        [
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
        ],
        roster: _boardedRoster([
          (id: 'r1', name: '김바래'),
          (id: 'r2', name: '이다솜'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('운행 종료 보류'), findsOneWidget);
    expect(find.text('08:30 마지막 승하차지에 도착했어요'), findsOneWidget);
    expect(find.textContaining('하차 대기 2명 · 전원이 내려야 운행이 끝나요'), findsOneWidget);
    expect(find.widgetWithText(BaraedaListRow, '김바래'), findsOneWidget);
    expect(find.widgetWithText(BaraedaButton, '보호자 부재 보고'), findsOneWidget);
  });

  // F06-14 — 도착 응답(§4.5) 스냅샷은 도착 순간의 값이다. 종료 화면은 도착 시각만 거기서 읽고, 하차 대기
  // 인원·종료 여부·다른 회차 구분은 지금의 명단·회차 목록·회차 표식으로 정한다.
  testWidgets('동승자가 하차를 처리해 명단이 줄면 하차 대기 인원도 따라 준다', (tester) async {
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
        // 도착 응답 뒤 r2 가 하차해 지금 탑승 중인 학생은 r1 하나다.
      ], roster: _boardedRoster([(id: 'r1', name: '김바래')])),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('하차 대기 1명'), findsOneWidget);
    expect(find.textContaining('하차 대기 2명'), findsNothing);
  });

  // Ruling 827 — 합계는 종료 뒤 §4.2 명단을 다시 받아 그린다(도착 응답의 낡은 값이 아니다).
  testWidgets('종료되면 명단을 다시 받아 하차 · 미승차 · 미등원 합계를 그린다', (tester) async {
    var fetches = 0;
    await tester.pumpWidget(
      _wrap(
        const RunEndScreen(),
        [
          selectedRunIdProvider.overrideWith((ref) => runId),
          lastArriveResultProvider.overrideWith(
            (ref) => _terminationWith(finishPending: false),
          ),
        ],
        roster: rosterProvider.overrideWith((ref) async {
          fetches++;
          return _finishedResponse(alighted: 13, noShow: 1, absentN: 2);
        }),
        runs: todayRunsProvider.overrideWith(
          (ref) async => [managerRunFixture(status: RunStatus.finished)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(fetches, greaterThanOrEqualTo(2), reason: '열릴 때 명단을 새로 받는다');
    expect(find.text('운행이 끝났어요'), findsOneWidget);
    expect(find.text('하차'), findsOneWidget);
    expect(find.text('미승차'), findsOneWidget);
    expect(find.text('미등원'), findsOneWidget);
    expect(find.text('13명'), findsOneWidget);
  });

  // R48 1순위 결함 — 하차 합계를 `counts.boarded` 로 그리면 운행이 끝난 뒤(전원 alighted) 항상 0 이 나왔다.
  testWidgets('전원이 하차한 종료 명단은 하차를 alighted 학생 수로 센다(counts.boarded 는 0)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const RunEndScreen(),
        [
          selectedRunIdProvider.overrideWith((ref) => runId),
          lastArriveResultProvider.overrideWith(
            (ref) => _terminationWith(finishPending: false),
          ),
        ],
        roster: _finishedRoster(alighted: 7, noShow: 1, absentN: 2),
        runs: todayRunsProvider.overrideWith(
          (ref) async => [managerRunFixture(status: RunStatus.finished)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 칸 하나 = 값 + 이름. 이름 칸의 부모 열에서 값을 읽어 "어느 칸이 몇 명인지" 를 묶어 본다.
    String valueOf(String label) {
      final column = find.ancestor(
        of: find.text(label),
        matching: find.byType(Column),
      );
      return tester
          .widget<Text>(
            find
                .descendant(of: column.first, matching: find.byType(Text))
                .first,
          )
          .textSpan!
          .toPlainText();
    }

    expect(valueOf('하차'), '7명');
    expect(valueOf('미승차'), '1명');
    expect(valueOf('미등원'), '2명');
  });

  testWidgets('회차가 종료됐으면 하차 대기 문구 대신 종료 안내를 보여준다', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RunEndScreen(),
        [
          selectedRunIdProvider.overrideWith((ref) => runId),
          lastArriveResultProvider.overrideWith(
            (ref) => _terminationWith(
              finishPending: true,
              remaining: const [
                RemainingRider(riderId: 'r1', name: '김바래', stopName: 'A정류장'),
              ],
            ),
          ),
        ],
        roster: _boardedRoster(const []),
        runs: todayRunsProvider.overrideWith(
          (ref) async => [managerRunFixture(status: RunStatus.finished)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('운행이 끝났어요'), findsOneWidget);
    expect(find.textContaining('하차 대기'), findsNothing);
  });

  testWidgets('다른 회차의 도착 스냅샷은 이 회차의 종료 화면에 쓰지 않는다', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RunEndScreen(),
        [
          selectedRunIdProvider.overrideWith((ref) => runId),
          lastArriveResultProvider.overrideWith(
            (ref) => _terminationWith(finishPending: true),
          ),
        ],
        // 스냅샷은 run-0 의 마지막 도착 처리에서 채워졌다.
        endedRun: transmissionEndedRunIdProvider.overrideWith((ref) => 'run-0'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('마지막 승하차지에 도착했어요'), findsNothing);
    expect(find.text('끝난 운행이 없어요'), findsOneWidget);
  });
}
