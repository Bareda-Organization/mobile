import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/features/home/presentation/widgets/run_card.dart';

/// R46 학부모 앱 홈 카드 — 지도 진입 표시(B2 #11) ·
/// 승인 대기 카운트다운(A #15, `FEATURE_SPEC P-03`) ·
/// 용어 통일(B2 #25, 사양 용어 "탑승 취소").
class _MutableClock implements Clock {
  new(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

final _now = DateTime(2026, 9, 12, 7, 10);

StudentRun _run({
  RunStatus runStatus = RunStatus.idle,
  bool confirmed = false,
  DateTime? departTime,
}) => StudentRun(
  runId: 'run-1',
  direction: RunDirection.toAcademy,
  busNo: '1호차',
  departTime: departTime ?? DateTime(2026, 9, 12, 8),
  runStatus: runStatus,
  confirmed: confirmed,
  riding: true,
  riderStatus: RiderStatus.waiting,
  stop: const RunStop(stopId: 'stop-1', name: '정문'),
  changeQuotaLeft: 1,
);

Future<void> _pump(
  WidgetTester tester, {
  required StudentRun run,
  DateTime? date,
  bool isApprovalPending = false,
  Clock? clock,
  List<String>? pushed,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: RunCard(
            studentId: 's-1',
            run: run,
            canToggle: true,
            date: date,
            isApprovalPending: isApprovalPending,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.liveMap,
        builder: (_, _) {
          pushed?.add(AppRoutes.liveMap);
          return const Scaffold(body: Text('지도 화면'));
        },
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(clock ?? _MutableClock(_now)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

void main() {
  group('B2 #11 지도 진입 표시', () {
    testWidgets('운행 중인 오늘 카드에 [실시간 위치 보기 ›] 가 있고 누르면 지도로 간다', (tester) async {
      final pushed = <String>[];
      await _pump(
        tester,
        run: _run(runStatus: RunStatus.moving, confirmed: true),
        pushed: pushed,
      );

      expect(find.text('실시간 위치 보기 ›'), findsOneWidget);

      await tester.tap(find.text('실시간 위치 보기 ›'));
      await tester.pumpAndSettle();
      expect(pushed, [AppRoutes.liveMap]);
    });

    testWidgets('운행 전·종료 카드와 내일 카드에는 진입 표시가 없다 — 볼 위치가 없다', (tester) async {
      await _pump(tester, run: _run());
      expect(find.textContaining('실시간 위치'), findsNothing);

      await _pump(
        tester,
        run: _run(runStatus: RunStatus.finished, confirmed: true),
      );
      expect(find.textContaining('실시간 위치'), findsNothing);

      await _pump(
        tester,
        run: _run(runStatus: RunStatus.moving, confirmed: true),
        date: DateTime(2026, 9, 13),
      );
      expect(find.textContaining('실시간 위치'), findsNothing);
    });
  });

  group('A #15 승인 대기 카운트다운(P-03)', () {
    testWidgets('승인 대기 중이면 출발까지 남은 시간을 분 단위로 보이고 1분마다 갱신한다', (tester) async {
      final clock = _MutableClock(DateTime(2026, 9, 12, 7, 30));
      await _pump(
        tester,
        run: _run(
          runStatus: RunStatus.confirmed,
          confirmed: true,
          departTime: DateTime(2026, 9, 12, 8),
        ),
        isApprovalPending: true,
        clock: clock,
      );
      expect(find.text('승인 대기 · 출발까지 30분'), findsOneWidget);

      clock.value = DateTime(2026, 9, 12, 7, 31);
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('승인 대기 · 출발까지 29분'), findsOneWidget);
    });

    testWidgets('승인 대기가 아니면 카운트다운 줄이 없다', (tester) async {
      await _pump(
        tester,
        run: _run(runStatus: RunStatus.confirmed, confirmed: true),
      );
      expect(find.textContaining('승인 대기'), findsNothing);
    });
  });

  // C-08 — 홈 카드(지도 진입 표시를 더한 뒤에도)에 ETA·"몇 곳 전"·탑승 인원 문구가 없다.
  testWidgets('C-08 운행 중 카드에도 ETA·몇 곳 전·탑승 인원 문구가 없다', (tester) async {
    await _pump(
      tester,
      run: _run(runStatus: RunStatus.moving, confirmed: true),
      isApprovalPending: true,
    );

    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .join('\n');
    expect(rendered, contains('실시간 위치 보기 ›'));
    expect(
      rendered,
      isNot(matches(RegExp(r'도착 예정|ETA|예상|곳 전|정거장 전|탑승 인원|\d+\s*명'))),
    );
  });

  group('B2 #25 용어 — 탑승 취소', () {
    testWidgets('스위치를 끄면 확인 창 제목과 버튼이 사양 용어 "탑승 취소" 다', (tester) async {
      await _pump(tester, run: _run());

      await tester.tap(find.byType(BaraedaSwitch));
      await tester.pumpAndSettle();

      expect(find.text('오늘 탑승을 취소할까요?'), findsOneWidget);
      expect(find.text('탑승 취소'), findsOneWidget);
      expect(find.text('탑승 끄기'), findsNothing);
      expect(find.textContaining('끌까요'), findsNothing);
    });
  });
}
