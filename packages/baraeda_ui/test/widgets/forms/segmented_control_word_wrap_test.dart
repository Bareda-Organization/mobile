import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 좁은 폭(375pt)·글자 1.3배에서 칸이 4개인 세그먼트 — 낱말 중간에서 줄이 바뀌면 "차량 고/장" 처럼 읽힌다(R46, B2 #16).
void main() {
  const options = [
    BaraedaSegmentedOption('prev', label: '이전 승하차지 대기'),
    BaraedaSegmentedOption('veh', label: '차량 고장'),
    BaraedaSegmentedOption('stu', label: '학생 응급'),
    BaraedaSegmentedOption('etc', label: '기타'),
  ];

  Future<void> pump(WidgetTester tester, {required bool wrapByWord}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: BaraedaTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(375, 700),
              textScaler: TextScaler.linear(1.3),
            ),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: BaraedaSegmentedControl(
                  options: options,
                  value: 'veh',
                  block: true,
                  wrapByWord: wrapByWord,
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('wrapByWord 면 낱말이 줄 한가운데서 끊기지 않는다', (tester) async {
    await pump(tester, wrapByWord: true);

    final oneLine = tester.getSize(find.text('이전')).height;
    for (final word in ['승하차지', '대기', '차량', '고장', '학생', '응급', '기타']) {
      expect(
        tester.getSize(find.text(word)).height,
        lessThan(oneLine * 1.5),
        reason: '$word 는 한 줄이어야 한다 — 두 줄이면 낱말이 중간에서 끊긴 것이다',
      );
    }
  });

  testWidgets('기본값은 예전 그대로 라벨 하나를 한 덩어리로 그린다', (tester) async {
    await pump(tester, wrapByWord: false);

    expect(find.text('차량 고장'), findsOneWidget);
  });
}
