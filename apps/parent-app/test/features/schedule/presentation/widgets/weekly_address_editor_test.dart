import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_entry.dart';
import 'package:parent_app/features/schedule/domain/weekly_address_repository.dart';
import 'package:parent_app/features/schedule/presentation/widgets/weekly_address_editor.dart';

/// 이월 2-2 — API_SPEC §3.7 `ADDRESS_VERIFICATION_FAILED` 가 이 화면에서
/// 실제로 안내 문구로 갈리는지 확인한다.
class _ThrowingWeeklyAddressRepository implements WeeklyAddressRepository {
  _ThrowingWeeklyAddressRepository(this.failure);

  final Failure failure;

  @override
  Future<List<WeeklyAddressEntry>> getWeeklyAddress(String studentId) =>
      throw UnimplementedError();

  @override
  Future<List<WeeklyAddressEntry>> updateWeeklyAddress(
    String studentId,
    List<WeeklyAddressEntry> entries,
  ) => Future.error(failure);
}

const _entry = WeeklyAddressEntry(
  weekday: Weekday.mon,
  direction: RunDirection.toAcademy,
  address: '서울시 강남구 1',
);

void main() {
  testWidgets('저장이 ADDRESS_VERIFICATION_FAILED 로 실패하면 재입력 안내 문구를 보여준다', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weeklyAddressRepositoryProvider.overrideWithValue(
            _ThrowingWeeklyAddressRepository(
              const Failure.api(
                statusCode: 422,
                code: 'ADDRESS_VERIFICATION_FAILED',
                message: '주소를 확인할 수 없습니다',
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: WeeklyAddressEditor(studentId: 's-1', entries: [_entry]),
          ),
        ),
      ),
    );

    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();

    expect(find.text('주소를 확인할 수 없습니다. 다시 입력해 주세요'), findsOneWidget);
  });
}
