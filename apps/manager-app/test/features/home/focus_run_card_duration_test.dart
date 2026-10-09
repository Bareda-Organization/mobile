import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/widgets/focus_run_card.dart';

import '../../support/manager_run_fixture.dart';

/// M-M2(M-07) — 기사 운행 카드에 예상 소요시간이 보인다. 값이 없으면(서버가 모르면) 지어내지 않는다.
void main() {
  Future<void> pump(
    WidgetTester tester,
    ManagerRun run, {
    bool forEscort = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FocusRunCard(
          run: run,
          now: DateTime(2026, 9, 30, 7, 30),
          caption: '다음 운행',
          forEscort: forEscort,
        ),
      ),
    ),
  );

  testWidgets('기사 카드에 예상 소요시간(분)이 보인다', (tester) async {
    await pump(tester, managerRunFixture(stopCount: 4));

    expect(find.textContaining('예상 소요 30분'), findsOneWidget);
  });

  testWidgets('60분이 넘으면 시간과 분으로 읽는다', (tester) async {
    await pump(tester, managerRunFixture(stopCount: 4, estDurationMin: 75));

    expect(find.textContaining('예상 소요 1시간 15분'), findsOneWidget);
  });

  testWidgets('예상 소요가 없으면 줄을 그리지 않는다', (tester) async {
    await pump(tester, managerRunFixture(stopCount: 4, estDurationMin: null));

    expect(find.textContaining('예상 소요'), findsNothing);
  });
}
