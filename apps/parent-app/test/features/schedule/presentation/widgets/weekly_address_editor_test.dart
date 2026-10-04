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
  new(this.failure);

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

  testWidgets('F05-14 저장이 네트워크 오류로 실패하면 네트워크 확인 문구를 보여준다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weeklyAddressRepositoryProvider.overrideWithValue(
            _ThrowingWeeklyAddressRepository(const Failure.network()),
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

    expect(find.text('네트워크 상태를 확인해 주세요'), findsOneWidget);
  });

  // F05-11 — 한 칸을 비우고 저장하면 14건 전체가 거절돼 다른 요일 수정분까지 함께 잃는다. 보내기 전에 막는다.
  testWidgets('F05-11 칸을 비운 채 저장하면 요청이 나가지 않고 어느 칸인지 안내한다', (tester) async {
    final repository = _RecordingWeeklyAddressRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weeklyAddressRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: WeeklyAddressEditor(studentId: 's-1', entries: [_entry]),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();

    expect(repository.saved, isEmpty);
    expect(find.textContaining('주소를 입력해 주세요'), findsOneWidget);
  });

  // R46 A — 검사 경고 뒤에 저장 버튼이 영구히 잠겨 화면을 나갔다 들어와야 했다.
  testWidgets('R46 칸을 비워 경고가 뜬 뒤 다시 채우면 저장할 수 있다', (tester) async {
    final repository = _RecordingWeeklyAddressRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weeklyAddressRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: WeeklyAddressEditor(studentId: 's-1', entries: [_entry]),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '서울시 강남구 9');
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();

    expect(repository.saved.single.address, '서울시 강남구 9');
  });

  // R48 — 요일 알약 하나를 고르면 그 요일의 등원 · 하원 두 칸이 나오고, 저장하지 않은 요일에는 점이 붙는다.
  group('R48 요일 알약', () {
    const monTo = WeeklyAddressEntry(
      weekday: Weekday.mon,
      direction: RunDirection.toAcademy,
      address: '월 등원 주소',
    );
    const monFrom = WeeklyAddressEntry(
      weekday: Weekday.mon,
      direction: RunDirection.fromAcademy,
      address: '월 하원 주소',
    );
    const tueTo = WeeklyAddressEntry(
      weekday: Weekday.tue,
      direction: RunDirection.toAcademy,
      address: '화 등원 주소',
    );
    const tueFrom = WeeklyAddressEntry(
      weekday: Weekday.tue,
      direction: RunDirection.fromAcademy,
      address: '화 하원 주소',
    );

    Future<_RecordingWeeklyAddressRepository> pumpFour(
      WidgetTester tester,
    ) async {
      final repository = _RecordingWeeklyAddressRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weeklyAddressRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: WeeklyAddressEditor(
                studentId: 's-1',
                entries: [monTo, monFrom, tueTo, tueFrom],
              ),
            ),
          ),
        ),
      );
      return repository;
    }

    testWidgets('등록된 요일만 알약에 나오고, 고른 요일의 등원 · 하원 두 칸만 보인다', (tester) async {
      await pumpFour(tester);

      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('월요일 · 등원', findRichText: true), findsOneWidget);
      expect(find.text('월요일 · 하원', findRichText: true), findsOneWidget);
      expect(find.text('화요일 · 등원', findRichText: true), findsNothing);

      await tester.tap(find.text('화'));
      await tester.pumpAndSettle();

      expect(find.text('화요일 · 등원', findRichText: true), findsOneWidget);
      expect(find.text('월요일 · 등원', findRichText: true), findsNothing);
    });

    testWidgets('고친 요일에만 ● 가 붙고 "저장하지 않은 변경" 띠가 나온다 — 되돌리면 사라진다', (
      tester,
    ) async {
      await pumpFour(tester);
      expect(find.text('저장하지 않은 변경이 있어요'), findsNothing);

      await tester.enterText(find.byType(TextField).first, '월 등원 주소 고침');
      await tester.pumpAndSettle();

      expect(find.text('월●'), findsOneWidget);
      expect(find.text('화●'), findsNothing);
      expect(find.text('저장하지 않은 변경이 있어요'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '월 등원 주소');
      await tester.pumpAndSettle();

      expect(find.text('월●'), findsNothing);
      expect(find.text('저장하지 않은 변경이 있어요'), findsNothing);
    });

    testWidgets('다른 요일을 보다 저장해도 고친 요일까지 전체가 한 번에 간다(저장은 일괄)', (tester) async {
      final repository = await pumpFour(tester);

      await tester.enterText(find.byType(TextField).first, '월 등원 주소 고침');
      await tester.tap(find.text('화'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장하기'));
      await tester.pumpAndSettle();

      expect(repository.saved, hasLength(4));
      expect(repository.saved.first.address, '월 등원 주소 고침');
    });
  });

  // R32 P11 — 등록된 주소가 하나도 없으면 편집할 칸이 없어 주소를 넣을 방법이 없었다.
  group('P11 빈 목록에서 추가', () {
    Future<_RecordingWeeklyAddressRepository> pumpEmpty(
      WidgetTester tester,
    ) async {
      final repository = _RecordingWeeklyAddressRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weeklyAddressRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: WeeklyAddressEditor(studentId: 's-1', entries: []),
            ),
          ),
        ),
      );
      return repository;
    }

    testWidgets('빈 목록에는 안내와 [추가] 버튼이 있다', (tester) async {
      await pumpEmpty(tester);

      expect(find.text('등록된 등하원 주소가 없어요'), findsOneWidget);
      expect(find.text('추가'), findsOneWidget);
    });

    testWidgets('[추가] 로 연 입력칸에 주소를 넣고 저장하면 그 주소가 서버로 간다', (tester) async {
      final repository = await pumpEmpty(tester);

      await tester.tap(find.text('추가'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '서울시 강남구 2');
      await tester.tap(find.text('저장하기'));
      await tester.pumpAndSettle();

      expect(repository.saved, hasLength(1));
      expect(repository.saved.single.weekday, Weekday.mon);
      expect(repository.saved.single.direction, RunDirection.toAcademy);
      expect(repository.saved.single.address, '서울시 강남구 2');
    });

    testWidgets('주소를 비워 두고 저장하면 요청이 나가지 않고 입력 안내를 보여준다', (tester) async {
      final repository = await pumpEmpty(tester);

      await tester.tap(find.text('추가'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장하기'));
      await tester.pumpAndSettle();

      expect(repository.saved, isEmpty);
      expect(find.text('주소를 입력해 주세요'), findsOneWidget);
    });
  });
}

/// 저장 요청을 기록하는 가짜.
class _RecordingWeeklyAddressRepository implements WeeklyAddressRepository {
  List<WeeklyAddressEntry> saved = const [];

  @override
  Future<List<WeeklyAddressEntry>> getWeeklyAddress(String studentId) async =>
      const [];

  @override
  Future<List<WeeklyAddressEntry>> updateWeeklyAddress(
    String studentId,
    List<WeeklyAddressEntry> entries,
  ) async {
    saved = entries;
    return entries;
  }
}
