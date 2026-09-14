import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/map/map_surface.dart';
import 'package:parent_app/core/map/naver/naver_map_adapter.dart';

// F4 이월 3번 / F5 목표 19 — `NaverMapAdapter` 가 화면에서 사라질 때
// (dispose) 마커 보간 프레임 타이머(`_frameTicker`)가 실제로 멈추는지
// 확인한다.
//
// 판단 근거 — 왜 `debugStartFrameTickerForTest` 훅을 쓰는가: 프로덕션에서
// `_frameTicker` 가 시작되는 유일한 경로는 실제 네이버 지도 SDK 의
// `onMapReady` 콜백(→ `_syncMarkers` → `_syncFrameTicker`)이다. 위젯 시험
// 환경에는 플랫폼 채널이 없어 `NaverMapInit.ensureInitialized` 가 끝내
// 실패하고(`MissingPluginException`), `FutureBuilder` 가 로딩 자리
// (`ColoredBox`)에 머무른 채 실제 `NaverMap` 위젯도, `onMapReady` 도 결코
// 오지 않는다 — 즉 이 경로는 위젯 시험으로 도달이 원천적으로 불가능하다
// (`naver_map_adapter.dart` 의 `build()`·`NaverMapInit` 문서 참고).
//
// 이 시험이 검사하려는 것은 "타이머가 어떻게 시작되는가" 가 아니라
// "dispose() 가 이미 도는 타이머를 멈추는가" 다. 그래서 시작 경로만
// 시험 전용 훅으로 우회하고, **`dispose()` 자체는 프로덕션 코드 그대로
// 밟는다** — `_frameTicker.stop()` 을 지우면 이 시험만 실패하는 것을
// 결함 심기로 직접 확인했다(원복 후 `git status --porcelain` 확인 완료,
// 판정 근거는 `report-P.md` 1항).
void main() {
  testWidgets('화면이 dispose 되면 마커 보간 프레임 타이머가 멈춘다', (
    tester,
  ) async {
    final key = GlobalKey<State<NaverMapAdapter>>();

    await tester.pumpWidget(
      MaterialApp(
        home: NaverMapAdapter(
          key: key,
          camera: const MapCamera(lat: 37.5, lng: 127),
        ),
      ),
    );
    await tester.pump();

    var tickCount = 0;
    (key.currentState! as dynamic).debugStartFrameTickerForTest(
      () => tickCount++,
    );

    const interval = Duration(milliseconds: 16);

    // 화면이 살아 있는 동안 최소 1회는 불렸다는 것을 먼저 확보한다 —
    // 그래야 뒤이은 "0회 증가" 가 "원래도 안 돌았다" 와 구별된다.
    await tester.pump(interval);
    expect(tickCount, greaterThan(0));

    // 화면을 완전히 다른 위젯으로 교체 — `_NaverMapAdapterState.dispose()`
    // 가 호출된다.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final tickCountAtDispose = tickCount;

    // dispose 이후 여러 주기를 흘려보내도 더는 늘지 않아야 한다.
    await tester.pump(interval * 3);
    expect(
      tickCount,
      tickCountAtDispose,
      reason: 'dispose() 가 프레임 타이머를 멈추지 않으면 화면이 사라진 '
          '뒤에도 setPosition 호출이 계속 늘어난다',
    );
  });
}
