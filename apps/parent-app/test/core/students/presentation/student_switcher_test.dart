import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';
import 'package:parent_app/core/students/presentation/student_switcher.dart';

List<Student> _students(int count) => [
  for (var i = 1; i <= count; i++)
    Student(studentId: 's-$i', name: '자녀$i', linkedAt: DateTime(2026)),
];

Future<ProviderContainer> _pump(WidgetTester tester, int count) async {
  final students = _students(count);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => StudentSwitcher(
              students: students,
              selectedId: ref.watch(selectedStudentIdProvider) ?? 's-1',
            ),
          ),
        ),
      ),
    ),
  );
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
}

void main() {
  // UF-P-02 · frontend Ruling 472 — 2~3명은 이름 칩, 4명 이상은 고르는 창.
  testWidgets('자녀 3명까지는 이름 칩이 나란히 보인다', (tester) async {
    await _pump(tester, 3);

    expect(find.byType(BaraedaFilterPill), findsNWidgets(3));
    expect(find.byType(BaraedaSelect), findsNothing);
  });

  testWidgets('L1 자녀 4명 이상이면 이름 칩 대신 고르는 창 하나다', (tester) async {
    await _pump(tester, 4);

    expect(find.byType(BaraedaFilterPill), findsNothing);
    expect(find.byType(BaraedaSelect), findsOneWidget);
  });

  testWidgets('L1 고르는 창에서 자녀를 고르면 그 자녀로 바뀐다', (tester) async {
    final container = await _pump(tester, 5);

    await tester.tap(find.byType(BaraedaSelect));
    await tester.pumpAndSettle();
    await tester.tap(find.text('자녀4').last);
    await tester.pumpAndSettle();

    expect(container.read(selectedStudentIdProvider), 's-4');
  });
}
