import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/runs/presentation/run_providers.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_entry.dart';
import 'package:parent_app/features/schedule/presentation/schedule_providers.dart';
import 'package:parent_app/features/schedule/presentation/schedule_screen.dart';

/// R48 일정 탭(시안 `schedule` · `--pending` · `--no-child`) — 날짜 알약 · 회차 · 처리 대기 띠
/// · 이력의 방향 · 날짜.
class _FixedClock implements Clock {
  const new(this._value);
  final DateTime _value;

  @override
  DateTime now() => _value;
}

// 세계 표준시 03:14 = 한국 시간 10월 3일(토) 12:14.
final _now = DateTime.utc(2026, 10, 3, 3, 14);

StudentRun _run() => StudentRun(
  runId: 'run-1',
  direction: RunDirection.toAcademy,
  busNo: '2호차',
  departTime: DateTime.utc(2026, 10, 3, 3, 20),
  runStatus: RunStatus.moving,
  confirmed: true,
  riding: true,
  riderStatus: RiderStatus.waiting,
  stop: const RunStop(stopId: 'st-1', name: '행복마을 입구'),
  changeQuotaLeft: 1,
);

WeeklyAddressEntry _entry(Weekday day) => WeeklyAddressEntry(
  weekday: day,
  direction: RunDirection.toAcademy,
  address: '주소',
);

Future<void> _pump(
  WidgetTester tester, {
  required ChangeRequestPage page,
  List<Student>? students,
  List<WeeklyAddressEntry>? weekly,
  bool showHistory = false,
  double height = 2400,
}) async {
  tester.view.physicalSize = Size(800, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        clockProvider.overrideWithValue(_FixedClock(_now)),
        scheduleShowHistoryProvider.overrideWith((ref) => showHistory),
        currentUserRoleProvider.overrideWith((ref) => UserRole.parent),
        myStudentsProvider.overrideWith(
          (ref) async =>
              students ??
              [
                Student(
                  studentId: 's-1',
                  name: '이하준',
                  linkedAt: DateTime(2026, 9),
                ),
              ],
        ),
        runsForStudentProvider.overrideWith((ref, id) async => [_run()]),
        weeklyAddressProvider.overrideWith(
          (ref, id) async =>
              weekly ?? [for (final d in Weekday.values.take(6)) _entry(d)],
        ),
        changeRequestsProvider.overrideWith((ref, id) async => page),
      ],
      child: const MaterialApp(home: ScheduleScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('머리줄에 오늘 날짜가, 날짜 알약에 오늘 · 내일 날짜가 한국 시간으로 보인다', (tester) async {
    await _pump(
      tester,
      page: const ChangeRequestPage(items: [], pendingCount: 0),
    );

    expect(find.text('10월 3일 (토)'), findsOneWidget);
    expect(find.text('오늘 · 10월 3일'), findsOneWidget);
    expect(find.text('내일 · 10월 4일'), findsOneWidget);
  });

  testWidgets('오늘 회차 칸 — 등원 · 출발 시각 · 승하차지 · 호차 · 탑승 여부 · 상태 칩', (
    tester,
  ) async {
    await _pump(
      tester,
      page: const ChangeRequestPage(items: [], pendingCount: 0),
    );

    expect(find.textContaining('등원 · '), findsWidgets);
    expect(find.text('행복마을 입구 · 2호차 · 탑승'), findsOneWidget);
    expect(find.text('이동 중'), findsOneWidget);
  });

  testWidgets('처리 대기가 없으면 맨 위 띠가 없다', (tester) async {
    await _pump(
      tester,
      page: const ChangeRequestPage(items: [], pendingCount: 0),
    );

    expect(find.textContaining('처리 대기'), findsNothing);
  });

  testWidgets('처리 대기가 1건이면 "처리 대기 1건 · 승인을 기다리고 있어요" 띠가 사라지지 않는다(UF-P-06)', (
    tester,
  ) async {
    await _pump(
      tester,
      page: const ChangeRequestPage(
        items: [
          ChangeRequest(
            changeRequestId: 'c1',
            type: ChangeRequestType.cancel,
            status: ChangeRequestStatus.pending,
          ),
        ],
        pendingCount: 1,
      ),
    );

    expect(find.text('처리 대기 1건'), findsOneWidget);
    expect(find.text('승인을 기다리고 있어요'), findsWidgets);
    expect(find.textContaining('확인하고 있어요'), findsNothing);
    expect(find.text('이력 보기'), findsOneWidget);
  });

  group('신청 이력의 방향 · 날짜(Ruling 824)', () {
    ChangeRequestPage page(ChangeRequest item) =>
        ChangeRequestPage(items: [item], pendingCount: 0);

    testWidgets('서버가 service_date · direction 을 주면 "탑승 취소 · 오늘 하원" 이다', (
      tester,
    ) async {
      await _pump(
        tester,
        page: page(
          ChangeRequest(
            changeRequestId: 'c1',
            type: ChangeRequestType.cancel,
            status: ChangeRequestStatus.approved,
            serviceDate: DateTime.utc(2026, 10, 3),
            direction: RunDirection.fromAcademy,
          ),
        ),
      );

      expect(find.text('탑승 취소 · 오늘 하원'), findsOneWidget);
    });

    testWidgets('다른 날이면 날짜로 쓰고, 내일이면 "내일" 이다', (tester) async {
      await _pump(
        tester,
        page: ChangeRequestPage(
          items: [
            ChangeRequest(
              changeRequestId: 'c1',
              type: ChangeRequestType.relocate,
              status: ChangeRequestStatus.approved,
              serviceDate: DateTime.utc(2026, 10, 4),
              direction: RunDirection.toAcademy,
            ),
            ChangeRequest(
              changeRequestId: 'c2',
              type: ChangeRequestType.cancel,
              status: ChangeRequestStatus.approved,
              serviceDate: DateTime.utc(2026, 9, 28),
              direction: RunDirection.toAcademy,
            ),
          ],
          pendingCount: 0,
        ),
      );

      expect(find.text('승하차지 변경 · 내일 등원'), findsOneWidget);
      expect(find.text('탑승 취소 · 9월 28일 등원'), findsOneWidget);
    });

    testWidgets('서버가 방향 · 날짜를 안 주면 종류만 쓴다(깨지지 않는다)', (tester) async {
      await _pump(
        tester,
        page: page(
          const ChangeRequest(
            changeRequestId: 'c1',
            type: ChangeRequestType.cancel,
            status: ChangeRequestStatus.approved,
          ),
        ),
      );

      expect(find.text('탑승 취소'), findsOneWidget);
    });

    testWidgets('반려 사유는 둘째 줄에, 상태 칩은 승인 · 반려로 가른다', (tester) async {
      await _pump(
        tester,
        page: ChangeRequestPage(
          items: [
            ChangeRequest(
              changeRequestId: 'c1',
              type: ChangeRequestType.relocate,
              status: ChangeRequestStatus.rejected,
              rejectReason: '노선 범위 밖이라 학원에서 반영하기 어려워요',
              requestedAt: DateTime.utc(2026, 9, 30, 0, 12),
              decidedAt: DateTime.utc(2026, 9, 30, 0, 40),
            ),
          ],
          pendingCount: 0,
        ),
      );

      expect(find.textContaining('반려: 노선 범위 밖이라'), findsOneWidget);
      expect(find.byType(BaraedaStatusPill), findsWidgets);
      expect(find.text('반려'), findsOneWidget);
    });
  });

  testWidgets('요일별 주소 행은 등록된 요일 구간을 요약한다 — 월 ~ 토 등록', (tester) async {
    await _pump(
      tester,
      page: const ChangeRequestPage(items: [], pendingCount: 0),
    );

    expect(find.text('월 ~ 토 등록 · 매주 같은 주소로 와요'), findsOneWidget);
    expect(find.text('일일 변경 신청'), findsOneWidget);
  });

  testWidgets('이어지지 않는 요일은 점으로 늘어놓는다', (tester) async {
    await _pump(
      tester,
      page: const ChangeRequestPage(items: [], pendingCount: 0),
      weekly: [_entry(Weekday.mon), _entry(Weekday.wed)],
    );

    expect(find.text('월 · 수 등록 · 매주 같은 주소로 와요'), findsOneWidget);
  });

  testWidgets('연결된 자녀가 없으면 연결 유도 화면이다(schedule--no-child)', (tester) async {
    await _pump(
      tester,
      page: const ChangeRequestPage(items: [], pendingCount: 0),
      students: const [],
    );

    expect(find.text('연결된 자녀가 없어요'), findsOneWidget);
    expect(find.text('자녀 연결하기'), findsOneWidget);
  });

  // R52 낮음 B9 — 영수증의 [신청 이력 보기] 로 들어오면 일정 탭이 신청 이력 자리까지 내려가 있다.
  double scrolled(WidgetTester tester) => tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .pixels;

  testWidgets('이력으로 내려가라는 표시가 있으면 일정 탭이 내려가 있다', (tester) async {
    await _pump(
      tester,
      page: const ChangeRequestPage(items: [], pendingCount: 0),
      showHistory: true,
      height: 500,
    );

    expect(scrolled(tester), greaterThan(0));
    expect(
      tester.getTopLeft(find.text('신청 이력')).dy,
      lessThan(500),
      reason: '신청 이력 제목이 화면 안에 있다',
    );
  });

  testWidgets('표시가 없으면 일정 탭은 맨 위에서 시작한다', (tester) async {
    await _pump(
      tester,
      page: const ChangeRequestPage(items: [], pendingCount: 0),
      height: 500,
    );

    expect(scrolled(tester), 0);
  });
}
