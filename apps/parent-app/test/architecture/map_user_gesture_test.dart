import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 지도 따라가기를 끄는 신호 — 사용자가 손으로 지도를 움직였을 때만 `MapSurface.onUserGesture` 가 불려야 한다.
///
/// R46 B2 #12 — 화면 시험은 콜백을 직접 부르고, 위젯 시험은 SDK 지도를 그리지 못한다(플랫폼 채널 부재).
/// 그래서 SDK 의 "카메라 변경 이유"가 그 콜백으로 이어지는 배선은 어댑터 본문을 읽어 판정한다
/// (`map_gesture_test.dart` 와 같은 방식). 이 배선이 빠지면 따라가기가 영영 꺼지지 않아 사용자가 옮긴
/// 지도를 2초마다 되돌린다 — 반대로 코드가 옮긴 카메라(`developer`)까지 신호로 보내면 따라가기가 저절로 꺼진다.
void main() {
  test('카메라 변경 이유가 gesture·control 일 때만 onUserGesture 를 부른다', () {
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

    final start = body.indexOf('onCameraChange:');
    expect(start, isNonNegative, reason: 'NaverMap 에 onCameraChange 배선이 없다');
    final block = body.substring(start, body.indexOf('},', start));
    expect(block, contains('NCameraUpdateReason.gesture'));
    expect(block, contains('NCameraUpdateReason.control'));
    expect(block, contains('widget.onUserGesture?.call()'));
    expect(
      block,
      isNot(contains('NCameraUpdateReason.developer')),
      reason: '코드가 옮긴 카메라를 사용자 조작으로 보내면 따라가기가 저절로 꺼진다',
    );
  });
}
