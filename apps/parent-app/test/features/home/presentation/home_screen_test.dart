import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/role_policy.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/change_requests/presentation/change_request_providers.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';
import '../../../support/no_bus_position.dart';

void main() {
  // R48 `Ruling 826` — 로그아웃은 설정 탭 맨 아래에만 있다. 2026-09-29 에 홈 머리말에 뒀던 것을 뺐다
  // (홈 머리말 시험은 `home_bus_preview_test.dart` 의 '머리줄').
  // R32 P1~P3 — 홈에서 갈 길이 없던 화면 3곳. 진입점이 눌려서 실제 경로로 가는지까지 본다.
  Future<List<String>> pumpHome(
    WidgetTester tester, {
    required UserRole role,
    List<Student> students = const [],
  }) async {
    final pushed = <String>[];
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
        for (final path in [
          AppRoutes.childLink,
          AppRoutes.schedule,
          AppRoutes.liveMap,
        ])
          GoRoute(
            path: path,
            builder: (_, _) {
              pushed.add(path);
              return Scaffold(body: Text('도착:$path'));
            },
          ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noBusPositionOverride,
          roleCapabilitiesProvider.overrideWithValue(RoleCapabilities.of(role)),
          myStudentIdProvider.overrideWith((ref) async => 's-1'),
          myStudentsProvider.overrideWith((ref) async => students),
          runsForStudentProvider.overrideWith(
            (ref, studentId) async => const <StudentRun>[],
          ),
          changeRequestsProvider.overrideWith(
            (ref, studentId) async =>
                const ChangeRequestPage(items: [], pendingCount: 0),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return pushed;
  }

  final children = [
    Student(studentId: 's-1', name: '첫째', linkedAt: DateTime(2026, 9)),
  ];

  testWidgets('P1 학생 홈에 [부모님과 연결하기] 진입이 있고 누르면 연결 화면으로 간다', (tester) async {
    final pushed = await pumpHome(tester, role: UserRole.student);

    await tester.tap(find.text('부모님과 연결하기'));
    await tester.pumpAndSettle();

    expect(pushed, [AppRoutes.childLink]);
  });

  testWidgets('P1 학부모 홈에는 [부모님과 연결하기] 가 없다', (tester) async {
    await pumpHome(tester, role: UserRole.parent, students: children);

    expect(find.text('부모님과 연결하기'), findsNothing);
  });

  // R48 — 일정은 아래 탭이 되고(`app_shell_test`), 자녀 추가는 설정 탭으로
  // 옮겼다(`settings_screen_r48_test`).
  // 홈 본문에 같은 진입이 또 남아 있으면 길이 두 개가 된다.
  testWidgets('P2 학부모 홈에는 [일정] 단추가 없다 — 일정은 아래 탭이다', (tester) async {
    final pushed = await pumpHome(
      tester,
      role: UserRole.parent,
      students: children,
    );

    expect(find.widgetWithText(BaraedaButton, '일정'), findsNothing);
    expect(pushed, isEmpty);
  });

  testWidgets('P2 학생 홈에는 [일정] 진입이 없다 — 조회 전용', (tester) async {
    await pumpHome(tester, role: UserRole.student);

    expect(find.text('일정'), findsNothing);
  });

  testWidgets('P3 학부모 홈에는 [자녀 추가] 가 없다 — 설정 탭으로 옮겼다', (tester) async {
    await pumpHome(tester, role: UserRole.parent, students: children);

    expect(find.text('자녀 추가'), findsNothing);
  });

  testWidgets('P3 학생 홈에는 [자녀 추가] 가 없다', (tester) async {
    await pumpHome(tester, role: UserRole.student);

    expect(find.text('자녀 추가'), findsNothing);
  });
}
