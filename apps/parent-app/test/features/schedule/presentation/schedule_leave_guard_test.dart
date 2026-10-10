import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/runs/presentation/run_providers.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_entry.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_repository.dart';
import 'package:parent_app/features/schedule/presentation/daily_change_screen.dart';
import 'package:parent_app/features/schedule/presentation/schedule_providers.dart';
import 'package:parent_app/features/schedule/presentation/weekly_address_screen.dart';

/// R32 P14 — 주소·변경 요청을 적다가 뒤로 가면 확인 없이 입력이 사라졌다. R48 에서 일정 화면이 탭이 되고
/// 편집 둘이 하위 화면(요일별 주소 · 일일 변경)이 되었다 — 두 화면 모두 같은 확인을 거친다.
/// 앞 화면 → [path] 로 들어가 Android 뒤로가기(`handlePopRoute`)를 눌러 본다.
Future<void> _pumpSchedule(
  WidgetTester tester, {
  String path = AppRoutes.weeklyAddress,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () => context.push(path),
            child: const Text('일정 열기'),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.weeklyAddress,
        builder: (_, _) => const WeeklyAddressScreen(),
      ),
      GoRoute(
        path: AppRoutes.dailyChange,
        builder: (_, _) => const DailyChangeScreen(),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        // 출발 08:00 보다 한참 이른 ① 구간.
        clockProvider.overrideWithValue(_FixedClock(DateTime(2026, 9, 12, 7))),
        currentUserRoleProvider.overrideWith((ref) => UserRole.parent),
        myStudentsProvider.overrideWith(
          (ref) async => [
            Student(studentId: 's-1', name: '첫째', linkedAt: DateTime(2026, 9)),
          ],
        ),
        weeklyAddressRepositoryProvider.overrideWithValue(_OkRepository()),
        weeklyAddressProvider.overrideWith(
          (ref, id) async => const [
            WeeklyAddressEntry(
              weekday: Weekday.mon,
              direction: RunDirection.toAcademy,
              address: '서울시 강남구 1',
            ),
          ],
        ),
        runsForStudentProvider.overrideWith(
          (ref, id) async => [
            StudentRun(
              runId: 'run-1',
              direction: RunDirection.toAcademy,
              busNo: '1호차',
              departTime: DateTime(2026, 9, 12, 8),
              runStatus: RunStatus.idle,
              confirmed: false,
              riding: true,
              riderStatus: RiderStatus.waiting,
              stop: const RunStop(stopId: 'stop-1', name: '정문'),
              changeQuotaLeft: 1,
            ),
          ],
        ),
        changeRequestsProvider.overrideWith(
          (ref, id) async => throw UnimplementedError(),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.tap(find.text('일정 열기'));
  await tester.pumpAndSettle();
}

class _FixedClock implements Clock {
  const new(this._value);
  final DateTime _value;

  @override
  DateTime now() => _value;
}

void main() {
  testWidgets('P14 입력한 것이 없으면 뒤로가기는 확인 없이 나간다', (tester) async {
    await _pumpSchedule(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('일정 열기'), findsOneWidget);
    expect(find.text('나가기'), findsNothing);
  });

  testWidgets('P14 주소를 고치다 뒤로가면 확인 창이 뜨고 [계속 입력] 이면 그대로 남는다', (tester) async {
    await _pumpSchedule(tester);
    await tester.enterText(
      find.widgetWithText(TextField, '서울시 강남구 1'),
      '서울시 강남구 9',
    );
    await tester.pump(); // 입력이 반영되어 뒤로가기 가드가 켜진 다음 프레임

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('나가기'), findsOneWidget);

    await tester.tap(find.text('계속 입력'));
    await tester.pumpAndSettle();

    expect(find.text('일정 열기'), findsNothing);
    expect(find.text('서울시 강남구 9'), findsOneWidget);
  });

  testWidgets('P14 확인 창에서 [나가기] 를 누르면 일정 화면을 떠난다', (tester) async {
    await _pumpSchedule(tester);
    await tester.enterText(
      find.widgetWithText(TextField, '서울시 강남구 1'),
      '서울시 강남구 9',
    );
    await tester.pump(); // 입력이 반영되어 뒤로가기 가드가 켜진 다음 프레임

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('나가기'));
    await tester.pumpAndSettle();

    expect(find.text('일정 열기'), findsOneWidget);
  });

  testWidgets('P14 고친 주소를 원래대로 되돌리면 확인 없이 나간다', (tester) async {
    await _pumpSchedule(tester);
    final field = find.widgetWithText(TextField, '서울시 강남구 1');
    await tester.enterText(field, '서울시 강남구 9');
    await tester.enterText(find.byType(TextField).first, '서울시 강남구 1');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('일정 열기'), findsOneWidget);
  });

  testWidgets('P14 변경 신청 사유를 적다 뒤로가도 확인 창이 뜬다(일일 변경 화면)', (tester) async {
    await _pumpSchedule(tester, path: AppRoutes.dailyChange);
    await tester.tap(find.text('등원 · 08:00 출발'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(BaraedaTextarea),
        matching: find.byType(TextField),
      ),
      '아파트 공사로 정문이 막혀요',
    );
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('나가기'), findsOneWidget);
    // 시안 `weekly-address--leave` 의 문구.
    expect(find.text('입력을 그만할까요?'), findsOneWidget);
    expect(find.text('저장하지 않은 내용은 사라져요.'), findsOneWidget);
  });

  testWidgets('P14 고친 주소를 저장한 뒤에는 뒤로가도 확인 없이 나간다', (tester) async {
    await _pumpSchedule(tester);
    await tester.enterText(
      find.widgetWithText(TextField, '서울시 강남구 1'),
      '서울시 강남구 9',
    );
    await tester.pump();
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('일정 열기'), findsOneWidget);
    expect(find.text('나가기'), findsNothing);
  });
}

/// 저장은 항상 성공한다.
class _OkRepository implements WeeklyAddressRepository {
  @override
  Future<List<WeeklyAddressEntry>> getWeeklyAddress(String studentId) async =>
      const [];

  @override
  Future<List<WeeklyAddressEntry>> updateWeeklyAddress(
    String studentId,
    List<WeeklyAddressEntry> entries,
  ) async => entries;
}
