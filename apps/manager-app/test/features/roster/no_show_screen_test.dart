import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/roster/data/models/no_show_contact_request.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/no_show_screen.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';

class _FixedClock implements Clock {
  const new(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

/// 연락 이력은 서버가 준 `no_show_case.contacts[]` 를 그대로 그린다(`Ruling 823`) — 시각 · 수단 ·
/// 결과뿐이다.
RosterResponse _rosterWith(List<NoShowContact> contacts) => RosterResponse(
  runId: 'run-1',
  busNo: '2호차',
  direction: RunDirection.toAcademy,
  counts: const RosterCounts(boarded: 0, waiting: 0, noShow: 1, absentN: 0),
  stops: [
    RosterStop(
      stopId: 'st1',
      seq: 1,
      name: '중앙공원 앞',
      students: [
        RosterStudent(
          riderId: 'r1',
          studentId: 's1',
          name: '오시우',
          photoUrl: null,
          guardianPhone: '010-****-1234',
          canGoAlone: false,
          status: RiderStatus.noShow,
          className: '초4 · 수학A',
          noShowCase: NoShowCase(
            caseId: 'c1',
            startedAt: DateTime(2026, 10, 3, 12, 31, 20),
            expiresAt: DateTime(2026, 10, 3, 12, 34, 20),
            contacts: contacts,
          ),
        ),
      ],
    ),
  ],
);

void main() {
  Future<void> pump(WidgetTester tester, List<NoShowContact> contacts) async {
    tester.view
      ..physicalSize = const Size(800, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(
            _FixedClock(DateTime(2026, 10, 3, 12, 33, 8)),
          ),
          selectedRunIdProvider.overrideWith((ref) => 'run-1'),
          rosterProvider.overrideWith((ref) async => _rosterWith(contacts)),
        ],
        child: const MaterialApp(home: NoShowScreen(riderId: 'r1')),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('연락 이력은 contacts[] 의 시각 · 수단 · 결과를 시각순으로 그린다', (tester) async {
    await pump(tester, [
      NoShowContact(
        attemptType: NoShowAttemptType.call,
        result: NoShowContactResult.noAnswer,
        attemptedAt: DateTime(2026, 10, 3, 12, 32, 5),
      ),
      NoShowContact(
        attemptType: NoShowAttemptType.message,
        result: NoShowContactResult.answered,
        attemptedAt: DateTime(2026, 10, 3, 12, 32, 40),
      ),
    ]);

    expect(find.text('연락 기록'), findsOneWidget);
    expect(find.text('2건'), findsOneWidget);
    expect(find.text('전화 · 무응답'), findsOneWidget);
    expect(find.text('12:32:05'), findsOneWidget);
    expect(find.text('문자 · 응답함'), findsOneWidget);
    expect(find.text('12:32:40'), findsOneWidget);
    // 위쪽 줄이 먼저 온 시각이다.
    expect(
      tester.getTopLeft(find.text('전화 · 무응답')).dy,
      lessThan(tester.getTopLeft(find.text('문자 · 응답함')).dy),
    );
  });

  testWidgets('메모를 받지 않으므로 "보호자 이름 문의" 같은 줄은 만들지 않는다', (tester) async {
    await pump(tester, [
      NoShowContact(
        attemptType: NoShowAttemptType.call,
        result: NoShowContactResult.noAnswer,
        attemptedAt: DateTime(2026, 10, 3, 12, 32, 5),
      ),
    ]);

    expect(find.textContaining('이름 문의'), findsNothing);
    expect(find.byType(BaraedaListRow), findsOneWidget);
    expect(find.text('1회 시도 · 무응답'), findsOneWidget);
  });

  testWidgets('기록이 없으면 비어 있다고 알리고 시도 횟수를 지어내지 않는다', (tester) async {
    await pump(tester, const []);

    expect(find.text('0건'), findsOneWidget);
    expect(find.text('아직 남긴 연락 기록이 없어요'), findsOneWidget);
    expect(find.text('아직 시도하지 않았어요'), findsOneWidget);
    expect(find.byType(BaraedaListRow), findsNothing);
  });

  testWidgets('연락 대기 남은 시간을 mm:ss 로 그린다', (tester) async {
    await pump(tester, const []);

    // 12:34:20 에 끝나고 지금은 12:33:08 — 1분 12초 남았다.
    expect(find.text('01:12'), findsOneWidget);
    expect(find.text('연락 대기 남음'), findsOneWidget);
  });
}
