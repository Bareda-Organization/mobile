import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/widgets/revert_confirm_sheet.dart';

/// M-M6(Ruling 308) — 승차·하차 취소 알림은 폐지됐다. 되돌리기 확인 창이 "알림이 새로 나가요" 라고 말하지 않는다.
RosterStudent _student(RiderStatus status) => RosterStudent(
  riderId: 'r1',
  studentId: 's1',
  name: '김바래',
  photoUrl: null,
  guardianPhone: null,
  canGoAlone: false,
  status: status,
);

void main() {
  Future<void> openSheet(WidgetTester tester, RiderStatus status) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showRevertConfirmSheet(context, student: _student(status)),
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  for (final status in [
    RiderStatus.boarded,
    RiderStatus.alighted,
    RiderStatus.noShow,
  ]) {
    testWidgets('${status.name} 되돌리기 확인 창에 취소 알림 문구가 없다', (tester) async {
      await openSheet(tester, status);

      expect(find.text('처리 기록은 지워지지 않고 남아요'), findsOneWidget);
      expect(find.textContaining('알림이'), findsNothing);
      expect(find.textContaining('취소'), findsNothing);
    });
  }
}
