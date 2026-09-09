// [RosterTable] 시험 — core 의존이 없어 pump 로 실제 확인 가능.
import 'package:baraeda_ui/theme/baraeda_theme.dart';
import 'package:baraeda_ui/widgets/transit/roster_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Student {
  const _Student(this.name, this.grade);

  final String name;
  final String grade;
}

void main() {
  final columns = <RosterColumn<_Student>>[
    RosterColumn<_Student>(
      key: 'name',
      label: '이름',
      cellBuilder: (context, row) => Text(row.name),
    ),
    RosterColumn<_Student>(
      key: 'grade',
      label: '학년',
      align: RosterColumnAlign.center,
      cellBuilder: (context, row) => Text(row.grade),
    ),
  ];

  const rows = [_Student('김민성', '3학년'), _Student('이서연', '2학년')];

  Widget wrap(Widget child) {
    return MaterialApp(
      theme: BaraedaTheme.light(),
      home: Scaffold(body: child),
    );
  }

  testWidgets('헤더 라벨을 그린다', (tester) async {
    await tester.pumpWidget(
      wrap(RosterTable<_Student>(columns: columns, rows: rows)),
    );

    expect(find.text('이름'), findsOneWidget);
    expect(find.text('학년'), findsOneWidget);
  });

  testWidgets('cellBuilder 로 각 행의 셀을 그린다', (tester) async {
    await tester.pumpWidget(
      wrap(RosterTable<_Student>(columns: columns, rows: rows)),
    );

    expect(find.text('김민성'), findsOneWidget);
    expect(find.text('3학년'), findsOneWidget);
    expect(find.text('이서연'), findsOneWidget);
    expect(find.text('2학년'), findsOneWidget);
  });

  testWidgets('행을 탭하면 onRowTap 이 그 행 값으로 호출된다', (tester) async {
    _Student? tapped;
    await tester.pumpWidget(
      wrap(
        RosterTable<_Student>(
          columns: columns,
          rows: rows,
          onRowTap: (row) => tapped = row,
        ),
      ),
    );

    await tester.tap(find.text('이서연'));
    await tester.pump();

    expect(tapped, rows[1]);
  });

  testWidgets('가로 스크롤 컨테이너(SingleChildScrollView)로 감싼다', (tester) async {
    await tester.pumpWidget(
      wrap(RosterTable<_Student>(columns: columns, rows: rows)),
    );

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scrollView.scrollDirection, Axis.horizontal);
  });
}
