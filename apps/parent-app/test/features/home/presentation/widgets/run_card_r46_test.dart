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
  DateTime? approvalDeadlineAt,
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
            approvalDeadlineAt: approvalDeadlineAt,
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

  // R52 `Ruling 870` — 마감은 출발 시각이 아니라 서버가 준 `deadline_at`
  // (운행 시작 또는 출발 + 10분 중 먼저)이다.
  group('A #15 승인 대기 카운트다운(P-03) · R52 870 마감 = deadline_at', () {
    final departTime = DateTime(2026, 9, 12, 8);
    // 서버 마감 = 출발 + 10분.
    final deadline = DateTime(2026, 9, 12, 8, 10);

    testWidgets('승인 대기 중이면 서버 마감까지 남은 시간을 분 단위로 보이고 1분마다 갱신한다', (tester) async {
      final clock = _MutableClock(DateTime(2026, 9, 12, 7, 30));
      await _pump(
        tester,
        run: _run(
          runStatus: RunStatus.confirmed,
          confirmed: true,
          departTime: departTime,
        ),
        isApprovalPending: true,
        approvalDeadlineAt: deadline,
        clock: clock,
      );
      expect(find.text('승인 대기 · 마감까지 40분'), findsOneWidget);

      clock.value = DateTime(2026, 9, 12, 7, 31);
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('승인 대기 · 마감까지 39분'), findsOneWidget);
    });

    testWidgets('출발 시각이 지나도 마감 전이면 카운트다운이 이어지고 탑승 스위치는 열려 있다', (tester) async {
      await _pump(
        tester,
        run: _run(
          runStatus: RunStatus.confirmed,
          confirmed: true,
          departTime: departTime,
        ),
        isApprovalPending: true,
        approvalDeadlineAt: deadline,
        clock: _MutableClock(DateTime(2026, 9, 12, 8, 5)),
      );

      expect(find.text('승인 대기 · 마감까지 5분'), findsOneWidget);
      expect(
        tester.widget<BaraedaSwitch>(find.byType(BaraedaSwitch)).onChanged,
        isNotNull,
      );
    });

    testWidgets('서버가 마감을 안 주면 시각을 지어내지 않고 "승인 대기" 만 보인다', (tester) async {
      await _pump(
        tester,
        run: _run(
          runStatus: RunStatus.confirmed,
          confirmed: true,
          departTime: departTime,
        ),
        isApprovalPending: true,
        clock: _MutableClock(DateTime(2026, 9, 12, 7, 30)),
      );

      expect(find.text('승인 대기'), findsOneWidget);
      expect(find.textContaining('까지'), findsNothing);
    });

    testWidgets('승인 대기가 아니면 카운트다운 줄이 없다', (tester) async {
      await _pump(
        tester,
        run: _run(runStatus: RunStatus.confirmed, confirmed: true),
      );
      expect(find.textContaining('승인 대기'), findsNothing);
    });

    testWidgets('출발 시각이 지났어도 운행 전(confirmed)이면 끄기에서 승인 요청 창이 열린다', (
      tester,
    ) async {
      await _pump(
        tester,
        run: _run(
          runStatus: RunStatus.confirmed,
          confirmed: true,
          departTime: departTime,
        ),
        clock: _MutableClock(DateTime(2026, 9, 12, 8, 5)),
      );
      await tester.tap(find.byType(BaraedaSwitch));
      await tester.pumpAndSettle();

      expect(find.textContaining('학원 관리자의 승인이 필요해요'), findsOneWidget);
      expect(find.text('승인 요청 보내기'), findsOneWidget);
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

  // R48 시안 `cancel-ride` · `--approval` · `--moving` — 구간마다 확인 단추의 글자와 색이
  // 다르다(P2).
  // ② 구간의 단추는 취소가 아니라 "요청" 이다 — 위험색(빨강)이 아니라 주 단추(초록)여야 취소가 즉시 되는 줄 아는 오해가 없다.
  group('R48 탑승 취소 확인 창 — 구간별 단추', () {
    BaraedaButton confirmButton(WidgetTester tester, String label) =>
        tester.widget<BaraedaButton>(find.widgetWithText(BaraedaButton, label));

    testWidgets('① 구간(확정 전) — "바로 반영돼요" · 탑승 취소(위험색)', (tester) async {
      await _pump(tester, run: _run());
      await tester.tap(find.byType(BaraedaSwitch));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('바로 반영돼요. 출발 30분 전(07:30)까지는 다시 탑승으로 바꿀 수 있어요.'),
        findsOneWidget,
      );
      expect(
        confirmButton(tester, '탑승 취소').variant,
        BaraedaButtonVariant.danger,
      );
      expect(find.text('닫기'), findsOneWidget);
    });

    testWidgets('② 구간(확정 뒤) — 단추 글자는 "승인 요청 보내기" 이고 위험색이 아니라 주 단추다', (
      tester,
    ) async {
      await _pump(tester, run: _run(confirmed: true));
      await tester.tap(find.byType(BaraedaSwitch));
      await tester.pumpAndSettle();

      expect(find.textContaining('학원 관리자의 승인이 필요해요'), findsOneWidget);
      // 마감은 출발 시각이 아니라 서버 `deadline_at` 이라 확인 창에는 시각을 적지 않는다(R52 870).
      expect(
        find.textContaining('운행이 시작되기 전까지 승인되지 않으면 자동으로 반려돼요'),
        findsOneWidget,
      );
      expect(find.textContaining('08:00 까지'), findsNothing);
      expect(find.text('탑승 취소'), findsNothing);
      expect(
        confirmButton(tester, '승인 요청 보내기').variant,
        BaraedaButtonVariant.primary,
      );
    });

    testWidgets('③ 구간(운행 중) — 되돌릴 수 없다 · 승하차지에 정차하지 않는다 · 탑승 취소(위험색)', (
      tester,
    ) async {
      await _pump(
        tester,
        run: _run(runStatus: RunStatus.moving, confirmed: true),
      );
      await tester.tap(find.byType(BaraedaSwitch));
      await tester.pumpAndSettle();

      expect(find.textContaining('다시 탑승으로 바꿀 수 없어요'), findsOneWidget);
      expect(find.textContaining('에는 정차하지 않아요'), findsOneWidget);
      expect(
        confirmButton(tester, '탑승 취소').variant,
        BaraedaButtonVariant.danger,
      );
    });
  });
}
