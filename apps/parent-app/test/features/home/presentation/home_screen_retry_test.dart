import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/auth/academy_contact.dart';
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

/// R32 P7 — 홈의 오류 상태 4곳에 [다시 시도] 가 있고(자녀 · 내 정보는 R48 부터 한 화면 `버스 정보를 불러오지
/// 못했어요`), 화면을 당겨서 새로고침할 수 있다.
/// 첫 호출은 실패하고 다음 호출부터 성공하는 provider 로, 버튼이 실제로 다시 불러오는지 본다.
final _child = Student(
  studentId: 's-1',
  name: '첫째',
  linkedAt: DateTime(2026, 9),
);

class _Calls {
  int students = 0;
  int studentId = 0;
  int runs = 0;
}

Future<_Calls> _pump(
  WidgetTester tester, {
  required UserRole role,
  bool failStudents = false,
  bool failStudentId = false,
  bool failRuns = false,
  String? savedContact,
}) async {
  final calls = _Calls();
  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 은 실패한 provider 를 알아서 다시 부른다 — 오류 띠가 보이도록 끈다.
      retry: (_, _) => null,
      overrides: [
          noBusPositionOverride,
        savedAcademyContactProvider.overrideWith((ref) async => savedContact),
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
    expect(find.text('버스 정보를 불러오지 못했어요'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(calls.students, 2);
    expect(find.text('버스 정보를 불러오지 못했어요'), findsNothing);
  });

  testWidgets('P7 내 정보 오류 띠의 [다시 시도] 가 다시 불러온다', (tester) async {
    final calls = await _pump(
      tester,
      role: UserRole.student,
      failStudentId: true,
    );
    expect(find.text('버스 정보를 불러오지 못했어요'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(calls.studentId, 2);
    expect(find.text('버스 정보를 불러오지 못했어요'), findsNothing);
  });

  testWidgets('P7 오늘 회차 오류 띠의 [다시 시도] 가 다시 불러온다', (tester) async {
    final calls = await _pump(tester, role: UserRole.parent, failRuns: true);
    expect(find.text('오늘 회차를 불러오지 못했습니다'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(calls.runs, 2);
    expect(find.text('오늘 회차를 불러오지 못했습니다'), findsNothing);
  });

  testWidgets('P7 화면을 아래로 당기면 회차를 다시 불러온다', (tester) async {
    final calls = await _pump(tester, role: UserRole.parent);
    expect(calls.runs, 1);

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(calls.runs, 2);
  });

  // R48 시안 `home-parent--error` — 못 불러왔을 때는 큰 그림 + 안내 + 채워진 [다시 시도],
  // 그 아래에 급할 때 거는 전화.
  group('R48 홈 오류 화면', () {
    BaraedaButton retryButton(WidgetTester tester) => tester
        .widget<BaraedaButton>(find.widgetWithText(BaraedaButton, '다시 시도'));

    testWidgets('[다시 시도] 는 화면의 주 단추(채움)이고 다시 불러오기 아이콘이 있다', (tester) async {
      await _pump(tester, role: UserRole.parent, failStudents: true);

      final button = retryButton(tester);
      expect(button.variant, BaraedaButtonVariant.primary);
      expect(button.icon, 'refresh');
      expect(
        find.textContaining('연결되면 자동으로 다시 불러와요'),
        findsOneWidget,
        reason: '왜 기다리면 되는지를 안내가 말한다',
      );
    });

    testWidgets('기기에 남긴 학원 문의처에 번호가 있으면 급할 때 거는 전화 줄이 있다', (tester) async {
      await _pump(
        tester,
        role: UserRole.parent,
        failStudents: true,
        savedContact: '학원 데스크 032-000-1100',
      );

      expect(find.text('버스가 급하게 궁금하면'), findsOneWidget);
      expect(find.text('학원 032-000-1100'), findsOneWidget);
      expect(find.text('전화'), findsOneWidget);
    });

    testWidgets('문의처가 없거나 번호 모양이 아니면 전화 줄이 없다', (tester) async {
      await _pump(
        tester,
        role: UserRole.parent,
        failStudents: true,
        savedContact: '학원에 직접 문의',
      );

      expect(find.text('버스가 급하게 궁금하면'), findsNothing);
      expect(find.text('전화'), findsNothing);
    });
  });
}
