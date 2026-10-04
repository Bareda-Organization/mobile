import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/runs/domain/bus_position.dart';
import 'package:parent_app/core/ui/delay_band.dart';

/// R49 F2 — 지연 띠의 사유 줄은 서버 코드(`traffic`)가 아니라 한글이다. 모르는 값이면 줄을 숨긴다.
void main() {
  Future<void> pump(WidgetTester tester, {String? reason, bool short = false}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: BaraedaTheme.light(),
        home: Scaffold(
          body: DelayBand(
            delay: BusDelay(
              minutes: 10,
              reason: reason,
              sentAt: DateTime.utc(2026, 10, 5, 3, 12),
            ),
            short: short,
          ),
        ),
      ),
    );
  }

  const labels = {
    'traffic': '교통 체증',
    'weather': '기상 악화',
    'vehicle_check': '차량 점검',
    'prev_stop_wait': '앞 승하차지 대기',
  };

  for (final MapEntry(key: code, value: label) in labels.entries) {
    testWidgets('사유 $code 는 "$label" 로 나오고 코드는 안 나온다', (tester) async {
      await pump(tester, reason: code);

      expect(find.text('버스가 10분 늦어요'), findsOneWidget);
      expect(find.text(label), findsOneWidget);
      expect(find.text(code), findsNothing);
    });
  }

  testWidgets('모르는 사유는 코드를 띄우지 않고 사유 줄을 숨긴다 — 띠 제목은 남는다', (tester) async {
    await pump(tester, reason: 'flat_tire');

    expect(find.text('버스가 10분 늦어요'), findsOneWidget);
    expect(find.text('flat_tire'), findsNothing);
    expect(find.byType(WordWrapText), findsOneWidget);
  });

  testWidgets('사유가 없으면 띠 제목만 나온다', (tester) async {
    await pump(tester);

    expect(find.byType(WordWrapText), findsOneWidget);
  });
}
