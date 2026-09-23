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
}
