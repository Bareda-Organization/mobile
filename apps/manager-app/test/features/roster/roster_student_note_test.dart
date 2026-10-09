import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_widgets.dart';

/// M-M1(RST-02 · M-03) — 명단의 학생 행은 이름 · 반 · 연락처 · 혼자 귀가 여부 · 상태와 함께
/// **특이사항**을 보인다.
RosterStudent _student({String? note}) => RosterStudent(
  riderId: 'r1',
  studentId: 's1',
  name: '김바래',
  photoUrl: null,
  guardianPhone: null,
  canGoAlone: true,
  status: RiderStatus.waiting,
  note: note,
);

void main() {
  Future<void> pump(WidgetTester tester, RosterStudent student) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RosterStudentTile(student: student, ride: RideStatus.waiting),
          ),
        ),
      );

  testWidgets('특이사항이 있으면 학생 행에 보인다', (tester) async {
    await pump(tester, _student(note: '견과류 알레르기'));

    expect(find.text('특이사항 · 견과류 알레르기'), findsOneWidget);
  });

  testWidgets('특이사항이 없거나 공백이면 줄을 그리지 않는다', (tester) async {
    await pump(tester, _student());
    expect(find.textContaining('특이사항'), findsNothing);

    await pump(tester, _student(note: '   '));
    expect(find.textContaining('특이사항'), findsNothing);
  });
}
