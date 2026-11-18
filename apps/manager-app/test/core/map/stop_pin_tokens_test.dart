import 'dart:io';

import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/map/stop_pin.dart';

/// 정차지 핀의 색은 디자인 토큰에서 온다 — 값을 파일에 직접 적으면 토큰이 바뀌어도 따라오지 않는다.
void main() {
  test('핀 색이 토큰과 같다', () {
    expect(StopPin.color, BaraedaPalette.green600);
    expect(StopPin.skippedColor, BaraedaPalette.stone400);
  });

  test('핀 파일에 색 값(Color(0x…))을 직접 적지 않는다', () {
    final source = File('lib/core/map/stop_pin.dart').readAsStringSync();

    expect(source, isNot(contains('Color(0x')));
  });
}
