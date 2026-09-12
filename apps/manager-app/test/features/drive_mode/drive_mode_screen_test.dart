import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_providers.dart';
import 'package:manager_app/features/drive_mode/presentation/drive_mode_screen.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';

Widget _wrap(Widget child, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

/// 도착 처리 대상이 없는 빈 명단 — 이 파일은 "운행 시작" 버튼의 출발
/// 시간 창(±10분) 게이팅만 본다.
const _emptyRoster = RosterResponse(
  runId: 'run-1',
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  counts: RosterCounts(boarded: 0, waiting: 0, noShow: 0, absentN: 0),
  stops: [],
);

/// 서버가 `START_WINDOW_CLOSED`(§4.4)로 막는 것과 같은 창을
/// [ManagerRun.startWindowFrom]·[startWindowTo] 로 미리 화면에서도
/// 판정한다 — 판정 기준 시각은 실제 `DateTime.now()` 다(이 코드베이스에
/// 시계 주입 추상화가 아직 없어 프로덕션과 같은 방식으로 잰다).
ManagerRun _managerRun({
  required DateTime startWindowFrom,
  required DateTime startWindowTo,
}) {
  return ManagerRun(
    runId: 'run-1',
    busNo: '3호차',
    direction: RunDirection.toAcademy,
    departTime: startWindowFrom.add(const Duration(minutes: 10)),
    origin: '기점',
    destination: '학원',
    estDurationMin: 30,
    runStatus: RunStatus.confirmed,
    confirmed: true,
    startWindowFrom: startWindowFrom,
    startWindowTo: startWindowTo,
    addedCount: 0,
    removedCount: 0,
    ackRequired: false,
  );
}

void main() {
  const runId = 'run-1';

  testWidgets('출발 시간 창 안이면 운행 시작 버튼을 보여준다', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      _wrap(const DriveModeScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        driveModeRunProvider.overrideWithValue(
          _managerRun(
            startWindowFrom: now.subtract(const Duration(minutes: 5)),
            startWindowTo: now.add(const Duration(minutes: 5)),
          ),
        ),
        driveModeRosterProvider.overrideWith((ref) async => _emptyRoster),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('운행 시작'), findsOneWidget);
    expect(find.text('운행 시작 가능 시간(출발 ±10분)이 아닙니다'), findsNothing);
  });

  testWidgets('출발 시간 창 밖이면 운행 시작 버튼 대신 안내 문구를 보여준다', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      _wrap(const DriveModeScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        driveModeRunProvider.overrideWithValue(
          _managerRun(
            startWindowFrom: now.add(const Duration(minutes: 20)),
            startWindowTo: now.add(const Duration(minutes: 40)),
          ),
        ),
        driveModeRosterProvider.overrideWith((ref) async => _emptyRoster),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('운행 시작'), findsNothing);
    expect(find.text('운행 시작 가능 시간(출발 ±10분)이 아닙니다'), findsOneWidget);
  });
}
