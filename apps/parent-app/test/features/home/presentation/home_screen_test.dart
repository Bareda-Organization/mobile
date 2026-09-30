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

void main() {
  // 2026-09-29 사용자 지적 "한번 로그인 되면 로그아웃이 안 돼" — 로그아웃이 홈 맨 아래 [설정]
  // 안쪽 맨 아래에만 있어 찾지 못했다. 매니저 앱처럼 홈 머리말에 둔다(학부모·학생 공통).
  testWidgets('홈 머리말의 [로그아웃] 이 확인 대화를 연다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roleCapabilitiesProvider.overrideWithValue(null),
          myStudentIdProvider.overrideWith((ref) async => 's-1'),
          runsForStudentProvider.overrideWith(
            (ref, studentId) async => const <StudentRun>[],
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();

    expect(find.text('로그아웃 하시겠습니까?'), findsOneWidget);
  });

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

  testWidgets('P1 학생 홈에 [부모 연결 코드] 진입이 있고 누르면 연결 화면으로 간다', (tester) async {
    final pushed = await pumpHome(tester, role: UserRole.student);

    await tester.tap(find.text('부모 연결 코드'));
    await tester.pumpAndSettle();

    expect(pushed, [AppRoutes.childLink]);
  });

  testWidgets('P1 학부모 홈에는 [부모 연결 코드] 가 없다', (tester) async {
    await pumpHome(tester, role: UserRole.parent, students: children);

    expect(find.text('부모 연결 코드'), findsNothing);
  });

  testWidgets('P2 학부모 홈에 처리 대기 0건이어도 [일정] 진입이 보이고 일정 화면으로 간다', (
    tester,
  ) async {
    final pushed = await pumpHome(
      tester,
      role: UserRole.parent,
      students: children,
    );

    await tester.tap(find.text('일정'));
    await tester.pumpAndSettle();

    expect(pushed, [AppRoutes.schedule]);
  });

  testWidgets('P2 학생 홈에는 [일정] 진입이 없다 — 조회 전용', (tester) async {
    await pumpHome(tester, role: UserRole.student);

    expect(find.text('일정'), findsNothing);
  });

  testWidgets('P3 자녀가 1명 이상이어도 [자녀 추가] 로 연결 화면에 간다', (tester) async {
    final pushed = await pumpHome(
      tester,
      role: UserRole.parent,
      students: children,
    );

    await tester.tap(find.text('자녀 추가'));
    await tester.pumpAndSettle();

    expect(pushed, [AppRoutes.childLink]);
  });

  testWidgets('P3 학생 홈에는 [자녀 추가] 가 없다', (tester) async {
    await pumpHome(tester, role: UserRole.student);

    expect(find.text('자녀 추가'), findsNothing);
  });
}
