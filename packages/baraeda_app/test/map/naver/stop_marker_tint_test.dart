import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 네이버 지도 어댑터가 칠하는 승하차지 핀 색은 디자인 토큰에서 온다.
void main() {
  test('어댑터 파일에 색 값(Color(0x…))을 직접 적지 않는다', () {
    final source = File('lib/map/naver/naver_map_adapter.dart')
        .readAsStringSync();

    expect(source, isNot(contains('Color(0x')));
  });
}
