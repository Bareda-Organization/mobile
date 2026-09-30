import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/map/naver/stop_pin.dart';
import 'package:manager_app/core/map/naver/waypoint_chip.dart';

/// 강제 경유 지점 칩(R39 Ruling 400) — 승하차지 핀과 모양이 다른 번호 없는 칩 + "경유" 글자.
/// 색만으로 가르지 않으므로 글자와 모양(핀 윤곽이 아닌 둥근 사각형)이 구분 수단이다.
void main() {
  testWidgets('"경유" 글자만 있고 번호는 없으며, 정해 둔 크기 그대로 그려진다', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: WaypointChip()),
      ),
    );

    expect(find.text('경유'), findsOneWidget);
    expect(find.textContaining(RegExp(r'\d')), findsNothing);
    expect(tester.getSize(find.byType(WaypointChip)), WaypointChip.size);
  });

  test('승하차지 핀과 윤곽이 다르다 — 핀은 세로로 긴 물방울, 칩은 가로로 긴 사각형이다', () {
    expect(WaypointChip.size.width, greaterThan(WaypointChip.size.height));
    expect(StopPin.size.height, greaterThan(StopPin.size.width));
  });
}
