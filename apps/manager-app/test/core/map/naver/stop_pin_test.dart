import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/map/naver/stop_pin.dart';

/// 정차지 핀(사용자 지시 2026-09-23 — 끝이 좌표를 가리키는 물방울 핀 + 순번).
///
/// 끝점이 좌표에 오는 것은 SDK 기본 기준점(아래 가운데)과 이 위젯의 "끝점 = 아래 끝" 이 맞물려야
/// 성립한다 — 위젯이 [StopPin.size] 보다 크게 그려지면 이미지 아래에 빈칸이 생겨 끝점이 좌표에서
/// 떠오른다. 그래서 크기를 고정한다.
void main() {
  testWidgets('핀 머리에 순번이 들어가고, 정해 둔 크기 그대로 그려진다', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: StopPin(seq: 15)),
      ),
    );

    expect(find.text('15'), findsOneWidget);
    expect(tester.getSize(find.byType(StopPin)), StopPin.size);
    expect(StopPin.size.height, greaterThan(StopPin.size.width));
  });

  // R39 Ruling 400 — 오늘 서지 않는 승하차지는 색만이 아니라 흐림과 번호 취소선으로도 다르다.
  testWidgets('skipped 핀은 번호에 취소선이 있고 흐리게 그려지며 크기는 그대로다', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: StopPin(seq: 2, skipped: true)),
      ),
    );

    final text = tester.widget<Text>(find.text('2'));
    expect(text.style?.decoration, TextDecoration.lineThrough);
    expect(
      tester.widget<Opacity>(find.byType(Opacity)).opacity,
      lessThan(1),
    );
    expect(tester.getSize(find.byType(StopPin)), StopPin.size);
  });

  testWidgets('정상 핀은 취소선도 흐림도 없다', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: StopPin(seq: 2)),
      ),
    );

    expect(tester.widget<Text>(find.text('2')).style?.decoration, isNull);
    expect(find.byType(Opacity), findsNothing);
  });
}
