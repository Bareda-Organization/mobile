import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/auth/presentation/widgets/academy_picker.dart';

/// A13 — 검색 결과가 쪽 크기(20)에 닿으면 더 있을 수 있다고 알린다.
void main() {
  const notice = '검색 결과가 많아요. 학원 이름을 더 자세히 입력해 주세요';

  Future<void> search(WidgetTester tester, int count) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AcademyPicker(
              onSearch: (_) async => [
                for (var i = 0; i < count; i++)
                  AcademySummary(
                    id: 'a$i',
                    name: '학원$i',
                    region: '부천',
                    code: 'C-$i',
                  ),
              ],
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '학원');
    await tester.tap(find.text('검색하기'));
    await tester.pumpAndSettle();
  }

  testWidgets('결과가 쪽 크기보다 적으면 안내가 없다', (tester) async {
    await search(tester, academySearchPageSize - 1);

    expect(find.text(notice), findsNothing);
  });

  testWidgets('결과가 쪽 크기(20건)에 닿으면 안내를 보인다', (tester) async {
    await search(tester, academySearchPageSize);

    expect(find.text(notice), findsOneWidget);
  });
}
