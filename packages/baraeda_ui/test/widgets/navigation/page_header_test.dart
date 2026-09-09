// [PageHeader] 시험 — core 의존이 없어 pump 로 실제 확인 가능.
import 'package:baraeda_ui/theme/baraeda_theme.dart';
import 'package:baraeda_ui/widgets/navigation/page_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: BaraedaTheme.light(),
      home: Scaffold(body: child),
    );
  }

  testWidgets('title·description 을 그린다', (tester) async {
    await tester.pumpWidget(
      wrap(const PageHeader(title: '학생 명부', description: '재원 중인 학생 목록입니다.')),
    );

    expect(find.text('학생 명부'), findsOneWidget);
    expect(find.text('재원 중인 학생 목록입니다.'), findsOneWidget);
  });

  testWidgets('actions·tabs 슬롯에 넣은 위젯을 그대로 그린다', (tester) async {
    await tester.pumpWidget(
      wrap(
        PageHeader(
          title: '학생 명부',
          // 테마 기본 ElevatedButton 은 전체 폭(Size.fromHeight)이라 Row 안에
          // 그대로 두면 무한 폭 제약 오류가 난다. actions 슬롯은 호출부가
          // 폭을 직접 정해야 하므로 여기서도 minimumSize 를 좁혀 준다.
          actions: ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () {},
            child: const Text('추가'),
          ),
          tabs: const Text('전체 · 등원 · 하원'),
        ),
      ),
    );

    expect(find.widgetWithText(ElevatedButton, '추가'), findsOneWidget);
    expect(find.text('전체 · 등원 · 하원'), findsOneWidget);
  });

  testWidgets('description·actions·tabs 를 안 주면 그리지 않는다', (tester) async {
    await tester.pumpWidget(wrap(const PageHeader(title: '학생 명부')));

    expect(find.text('학생 명부'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
  });
}
