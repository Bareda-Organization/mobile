import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/role_policy.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/change_requests/presentation/change_request_providers.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/features/home/domain/notification_item.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';

/// R32 P7 — 홈의 오류 띠 4곳에 [다시 시도] 가 있고, 화면을 당겨서 새로고침할 수 있다.
/// 첫 호출은 실패하고 다음 호출부터 성공하는 provider 로, 버튼이 실제로 다시 불러오는지 본다.
const _emptyPage = NotificationPage(
  items: [],
  page: 1,
  size: 20,
  totalCount: 0,
  hasNext: false,
  unreadCount: 0,
);

final _child = Student(
  studentId: 's-1',
  name: '첫째',
  linkedAt: DateTime(2026, 9),
);

class _Calls {
  int students = 0;
  int studentId = 0;
  int runs = 0;
  int notifications = 0;
}

Future<_Calls> _pump(
  WidgetTester tester, {
  required UserRole role,
  bool failStudents = false,
  bool failStudentId = false,
  bool failRuns = false,
  bool failNotifications = false,
}) async {
  final calls = _Calls();
  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 은 실패한 provider 를 알아서 다시 부른다 — 오류 띠가 보이도록 끈다.
      retry: (_, _) => null,
      overrides: [
        roleCapabilitiesProvider.overrideWithValue(RoleCapabilities.of(role)),
        myStudentsProvider.overrideWith((ref) async {
          calls.students++;
          if (failStudents && calls.students == 1) throw Exception('x');
          return [_child];
        }),
        myStudentIdProvider.overrideWith((ref) async {
          calls.studentId++;
          if (failStudentId && calls.studentId == 1) throw Exception('x');
          return 's-1';
        }),
        runsForStudentProvider.overrideWith((ref, id) async {
          calls.runs++;
          if (failRuns && calls.runs == 1) throw Exception('x');
          return const <StudentRun>[];
        }),
        notificationsProvider.overrideWith((ref) async {
          calls.notifications++;
          if (failNotifications && calls.notifications == 1) {
            throw Exception('x');
          }
          return _emptyPage;
        }),
        changeRequestsProvider.overrideWith(
          (ref, id) async =>
              const ChangeRequestPage(items: [], pendingCount: 0),
        ),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

void main() {
  testWidgets('P7 자녀 목록 오류 띠의 [다시 시도] 가 다시 불러온다', (tester) async {
    final calls = await _pump(
      tester,
      role: UserRole.parent,
      failStudents: true,
    );
    expect(find.text('자녀 목록을 불러오지 못했습니다'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(calls.students, 2);
    expect(find.text('자녀 목록을 불러오지 못했습니다'), findsNothing);
  });

  testWidgets('P7 내 정보 오류 띠의 [다시 시도] 가 다시 불러온다', (tester) async {
    final calls = await _pump(
      tester,
      role: UserRole.student,
      failStudentId: true,
    );
    expect(find.text('내 정보를 불러오지 못했습니다'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(calls.studentId, 2);
    expect(find.text('내 정보를 불러오지 못했습니다'), findsNothing);
  });

  testWidgets('P7 오늘 회차 오류 띠의 [다시 시도] 가 다시 불러온다', (tester) async {
    final calls = await _pump(tester, role: UserRole.parent, failRuns: true);
    expect(find.text('오늘 회차를 불러오지 못했습니다'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(calls.runs, 2);
    expect(find.text('오늘 회차를 불러오지 못했습니다'), findsNothing);
  });

  testWidgets('P7 알림 오류 띠의 [다시 시도] 가 다시 불러온다', (tester) async {
    final calls = await _pump(
      tester,
      role: UserRole.parent,
      failNotifications: true,
    );
    expect(find.text('알림을 불러오지 못했습니다'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(calls.notifications, 2);
    expect(find.text('알림을 불러오지 못했습니다'), findsNothing);
  });

  testWidgets('P7 화면을 아래로 당기면 회차·알림을 다시 불러온다', (tester) async {
    final calls = await _pump(tester, role: UserRole.parent);
    expect(calls.notifications, 1);
    expect(calls.runs, 1);

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(calls.notifications, 2);
    expect(calls.runs, 2);
  });
}
