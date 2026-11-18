import 'package:baraeda_app/baraeda_app.dart';
import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<AcademySummary> _academies(int count) => [
  for (var i = 1; i <= count; i++)
    AcademySummary(id: 'a-$i', name: '학원$i', region: '부천시', code: 'C$i'),
];

/// 검색어를 넣고 [검색] 단추를 눌러 [resultCount] 건을 돌려받은 화면.
Future<List<AcademySummary>> _search(
  WidgetTester tester,
  AcademyPickerStyle style,
  int resultCount,
) async {
  final picked = <AcademySummary>[];
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AcademyPicker(
            style: style,
            onSearch: (_) async => _academies(resultCount),
            onSelected: picked.add,
          ),
        ),
      ),
    ),
  );
  await tester.enterText(find.byType(TextField), '학원');
  await tester.tap(find.widgetWithText(BaraedaButton, style.searchLabel));
  await tester.pumpAndSettle();
  return picked;
}

/// 학원 검색 — 두 앱이 같은 검색 흐름을 쓰고 결과를 보이는 모양(목록 · 드롭다운)만 다르다.
void main() {
  for (final style in AcademyPickerStyle.values) {
    group('$style', () {
      // API_SPEC §2.1 — 서버는 최대 20건만 주고 잘렸다는 표시를 하지 않는다.
      testWidgets('결과가 쪽 크기(20건)에 닿으면 좁히라는 안내를 보인다', (tester) async {
        await _search(tester, style, academySearchPageSize);

        expect(find.text(style.tooManyNotice), findsOneWidget);
      });

      testWidgets('결과가 쪽 크기보다 적으면 그 안내가 없다', (tester) async {
        await _search(tester, style, academySearchPageSize - 1);

        expect(find.text(style.tooManyNotice), findsNothing);
      });

      testWidgets('결과가 없으면 학원에 문의하라는 안내를 보인다', (tester) async {
        await _search(tester, style, 0);

        expect(find.text('학원을 찾을 수 없어요 — 학원에 문의해 주세요'), findsOneWidget);
      });
    });
  }

  testWidgets('목록 모양은 줄을 누르면 그 학원이 선택된다', (tester) async {
    final picked = await _search(tester, AcademyPickerStyle.radioList, 3);

    await tester.tap(find.text('학원2'));

    expect(picked.single.id, 'a-2');
  });

  testWidgets('드롭다운 모양은 한 건을 고르면 그 학원이 선택된다', (tester) async {
    final picked = await _search(tester, AcademyPickerStyle.dropdown, 3);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('학원3').last);
    await tester.pumpAndSettle();

    expect(picked.single.id, 'a-3');
  });
}
