import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 승하차지 번호 핀의 색은 디자인 토큰에서 온다 — 값을 파일에 직접 적지 않는다.
void main() {
  for (final path in [
    'lib/core/map/stop_number_pin.dart',
    'lib/core/map/parent_map_options.dart',
  ]) {
    test('$path 에 색 값(Color(0x…))을 직접 적지 않는다', () {
      final source = File(path).readAsStringSync();

      expect(source, isNot(contains('Color(0x')));
    });
  }

  test('번호 핀이 지도 색 토큰을 쓴다', () {
    final source = File('lib/core/map/stop_number_pin.dart').readAsStringSync();

    expect(source, contains('BaraedaMapColors.'));
  });
}
