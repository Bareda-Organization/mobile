// 승하차지 타임라인 — 상태마다 번호 원의 모양이 다르다(시안 kit "승하차지 타임라인").
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: BaraedaTheme.light(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  const colors = BaraedaColors.light;

  testWidgets('번호 원: 지난 곳은 체크, 나머지는 순서 번호', (tester) async {
    await tester.pumpWidget(
      _host(
        const StopTimeline(
          stops: [
            Stop(name: '푸른아파트 앞', state: StopState.done),
            Stop(name: '중앙공원 앞', state: StopState.current),
            Stop(name: '행복마을 입구', state: StopState.next),
            Stop(name: '한빛빌라', state: StopState.skipped),
            Stop(name: '달빛어린이집', state: StopState.added),
          ],
        ),
      ),
    );
    expect(find.text('1'), findsNothing); // 지난 곳은 숫자 대신 체크 아이콘
    expect(find.byIcon(Icons.check), findsOneWidget);
    for (final n in ['2', '3', '4', '5']) {
      expect(find.text(n), findsOneWidget);
    }
  });

  testWidgets('지금 곳은 32, 나머지는 28 크기의 원', (tester) async {
    await tester.pumpWidget(
      _host(
        const StopTimeline(
          stops: [
            Stop(name: 'A', state: StopState.done),
            Stop(name: 'B', state: StopState.current),
            Stop(name: 'C'),
          ],
        ),
      ),
    );
    Size circle(String text) => tester.getSize(
      find
          .ancestor(of: find.text(text), matching: find.byType(Container))
          .first,
    );
    expect(circle('2'), const Size(32, 32));
    expect(circle('3'), const Size(28, 28));
  });

  testWidgets('건너뜀은 취소선 + 위험 글자, 이름은 두 줄에서 `…`', (tester) async {
    await tester.pumpWidget(
      _host(
        StopTimeline(
          stops: [
            const Stop(name: '한빛빌라', state: StopState.skipped),
            Stop(name: '긴 이름 승하차지 ' * 8),
          ],
        ),
      ),
    );
    final skipped = tester.widget<Text>(find.text('한빛빌라'));
    expect(skipped.style!.decoration, TextDecoration.lineThrough);
    expect(skipped.style!.color, colors.statusMissed);
    final long = tester.widget<Text>(find.textContaining('긴 이름'));
    expect(long.maxLines, 2);
    expect(long.overflow, TextOverflow.ellipsis);
  });

  testWidgets('한 줄 높이는 56 이상', (tester) async {
    await tester.pumpWidget(
      _host(const StopTimeline(stops: [Stop(name: '짧은 이름')])),
    );
    expect(
      tester.getSize(find.byType(StopTimeline)).height,
      greaterThanOrEqualTo(BaraedaSpacing.rowMinHeight),
    );
  });
}
