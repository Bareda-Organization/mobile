import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/features/auth/presentation/widgets/academy_picker.dart';

List<AcademySummary> _academies(int count) => [
  for (var i = 1; i <= count; i++)
    AcademySummary(id: 'a-$i', name: '학원$i', region: '부천시', code: 'C$i'),
];

Future<void> _search(WidgetTester tester, int resultCount) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AcademyPicker(
            onSearch: (_) async => _academies(resultCount),
            onSelected: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.enterText(find.byType(TextField), '학원');
  await tester.tap(find.widgetWithText(BaraedaButton, '검색'));
  await tester.pumpAndSettle();
}

void main() {
  // API_SPEC §2.1 — 서버는 최대 20건만 주고 잘렸다는 표시를 하지 않는다. 20건이면 검색어를 좁히라고 안내한다.
  testWidgets('L3 결과가 20건이면 검색어를 좁히라는 안내가 나온다', (tester) async {
    await _search(tester, 20);

    expect(find.text('학원1'), findsOneWidget);
    expect(find.textContaining('검색어를 더 자세히'), findsOneWidget);
  });

  testWidgets('L3 결과가 20건보다 적으면 그 안내가 없다', (tester) async {
    await _search(tester, 19);

    expect(find.text('학원1'), findsOneWidget);
    expect(find.textContaining('검색어를 더 자세히'), findsNothing);
  });
}
