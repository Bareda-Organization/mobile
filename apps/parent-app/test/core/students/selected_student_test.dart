import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/students/data/selected_student_storage.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';
import 'package:parent_app/core/students/presentation/student_switcher.dart';

/// R46 B2 #13 — 다자녀: 고른 자녀를 앱을 다시 켠 뒤에도 기억하고, 전환은 한 번 누름으로 끝난다.
class _MemoryStorage extends SelectedStudentStorage {
  _MemoryStorage() : saved = null;

  String? saved;

  @override
  Future<String?> read() async => saved;

  @override
  Future<void> save(String studentId) async => saved = studentId;
}

Student _child(String id, String name) =>
    Student(studentId: id, name: name, linkedAt: DateTime(2026));

void main() {
  group('pickStudentId', () {
    final students = [_child('s-1', '첫째'), _child('s-2', '둘째')];

    test('이번 실행에서 고른 자녀가 기억해 둔 자녀보다 먼저다', () {
      expect(
        pickStudentId(students, picked: 's-1', saved: 's-2'),
        's-1',
      );
    });

    test('고른 적이 없으면 기억해 둔 자녀를 쓴다', () {
      expect(pickStudentId(students, saved: 's-2'), 's-2');
    });

    test('연결이 끊긴 자녀나 다른 계정의 기억은 버리고 첫 자녀로 간다', () {
      expect(pickStudentId(students, saved: 's-9'), 's-1');
      expect(pickStudentId(students, picked: 's-9'), 's-1');
      expect(pickStudentId(students), 's-1');
    });
  });

  group('StudentSwitcher', () {
    Future<ProviderContainer> pump(
      WidgetTester tester,
      List<Student> students,
      _MemoryStorage storage,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            selectedStudentStorageProvider.overrideWithValue(storage),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => StudentSwitcher(
                  students: students,
                  selectedId: pickStudentId(
                    students,
                    picked: ref.watch(selectedStudentIdProvider),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return ProviderScope.containerOf(
        tester.element(find.byType(StudentSwitcher)),
        listen: false,
      );
    }

    testWidgets('자녀가 1명이면 아무것도 그리지 않는다', (tester) async {
      await pump(tester, [_child('s-1', '첫째')], _MemoryStorage());
      expect(find.byType(BaraedaSegmentedControl), findsNothing);
      expect(find.byType(BaraedaSelect), findsNothing);
    });

    testWidgets('자녀 2~3명은 이름이 나란히 보이고 한 번 누르면 바뀌며 기억한다', (tester) async {
      final storage = _MemoryStorage();
      final container = await pump(
        tester,
        [_child('s-1', '첫째'), _child('s-2', '둘째')],
        storage,
      );
      expect(find.text('첫째'), findsOneWidget);
      expect(find.text('둘째'), findsOneWidget);

      await tester.tap(find.text('둘째'));
      await tester.pump();

      expect(container.read(selectedStudentIdProvider), 's-2');
      expect(storage.saved, 's-2');
    });

    testWidgets('자녀 3명도 이름이 나란히 보인다 — 칩의 최대 수는 3명이다', (tester) async {
      await pump(
        tester,
        [for (var i = 1; i <= 3; i++) _child('s-$i', '자녀$i')],
        _MemoryStorage(),
      );
      expect(find.byType(BaraedaSegmentedControl), findsOneWidget);
      expect(find.byType(BaraedaSelect), findsNothing);
    });

    testWidgets('자녀 4명 이상은 이름이 좁아 고르는 창(드롭다운)으로 둔다', (tester) async {
      await pump(
        tester,
        [for (var i = 1; i <= 4; i++) _child('s-$i', '자녀$i')],
        _MemoryStorage(),
      );
      expect(find.byType(BaraedaSelect), findsOneWidget);
      expect(find.byType(BaraedaSegmentedControl), findsNothing);
    });
  });
}
