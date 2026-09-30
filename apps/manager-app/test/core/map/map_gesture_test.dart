import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 지도가 스크롤 뷰 안에 놓여도 손가락 이동·확대가 지도에 닿는지 지키는 검사.
///
/// R41-CHK — `NaverMap` 은 `forceGesture` 기본값이 `false` 라 운행 화면처럼
/// `SingleChildScrollView` 안에서는 끌기가 페이지 스크롤로 넘어가 지도가 움직이지
/// 않았다(iOS 시뮬레이터 실제 마우스 드래그에 지도 대신 페이지가 스크롤됨). 위젯
/// 시험은 SDK 초기화가 없어 `NaverMap` 을 그리지 못하므로 어댑터 본문을 읽어 판정한다.
void main() {
  test('NaverMap 은 스크롤 뷰 안에서도 제스처를 먼저 받도록 forceGesture: true 로 만든다', () {
    final source = File(
      '${Directory.current.path}/lib/core/map/naver/naver_map_adapter.dart',
    ).readAsStringSync();
    final body = source
        .split('\n')
        .map((line) {
          final i = line.indexOf('//');
          return i == -1 ? line : line.substring(0, i);
        })
        .join('\n');

    final start = body.indexOf('NaverMap(');
    expect(start, isNonNegative, reason: 'NaverMap( 생성부를 찾을 수 없다');
    final end = body.indexOf('onMapReady', start);
    expect(
      body.substring(start, end).contains('forceGesture: true'),
      isTrue,
      reason: 'NaverMap 에 forceGesture: true 가 없다 — ListView 안에서 지도를 끌 수 없다',
    );
  });
}
