import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// 지도 핀 · 노선 색은 사용자가 이미 보고 있는 값 그대로다 — 토큰으로 옮겨도 눈에 보이는 색이 바뀌지 않는다.
void main() {
  test('핀 · 노선 색이 지금 화면에 나오는 값과 같다', () {
    expect(BaraedaMapColors.stopPin, const Color(0xFF16A34A));
    expect(BaraedaMapColors.stopPinSkipped, const Color(0xFF9CA3AF));
    expect(BaraedaMapColors.stopMarkerTint, const Color(0xFFE08A00));
    expect(BaraedaMapColors.mapPlaceholder, const Color(0xFFE0E0E0));
    expect(BaraedaMapColors.numberPinAccent, const Color(0xFF1F5C4D));
    expect(BaraedaMapColors.numberPinInk, const Color(0xFF3D4441));
    expect(BaraedaMapColors.routeAhead, const Color(0xFF1F5C4D));
    expect(BaraedaMapColors.routePassed, const Color(0xFF8F9995));
  });
}
