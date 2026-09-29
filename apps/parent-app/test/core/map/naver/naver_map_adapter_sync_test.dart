import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/map/map_surface.dart';
import 'package:parent_app/core/map/naver/naver_map_adapter.dart';

/// 오버레이 추가·삭제가 끝나기를 시험이 풀어 줄 때까지 붙잡아 두고, 동시에 진행 중인 호출 수의 최댓값을 센다.
class _BlockingController extends Fake implements NaverMapController {
  final List<Completer<void>> gates = [];
  int inFlight = 0;
  int maxInFlight = 0;

  Future<void> _enter() async {
    inFlight++;
    maxInFlight = max(maxInFlight, inFlight);
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    inFlight--;
  }

  @override
  Future<void> addOverlayAll(Set<NAddableOverlay> overlays) => _enter();

  @override
  Future<void> deleteOverlay(NOverlayInfo info) => _enter();
}

Widget _adapter(GlobalKey key, String markerId) => MaterialApp(
  home: NaverMapAdapter(
    key: key,
    camera: const MapCamera(lat: 37.5, lng: 127),
    markers: [
      MapMarker(id: markerId, lat: 37.5, lng: 127, kind: MapMarkerKind.bus),
    ],
  ),
);

// R33 P2 — 마커 동기화가 겹쳐 시작되면 iOS 에서 핀 이미지가 빈 파일로 저장돼 앱이 종료된다(R32 M1).
// 어댑터가 동기화를 `SerialSync` 로 한 번에 하나만 돌리는지, 앞 동기화가 끝나기 전에 위젯이 두 번 갱신되는 것으로 확인한다.
void main() {
  testWidgets('마커가 연달아 바뀌어도 오버레이 동기화는 한 번에 하나만 돈다', (tester) async {
    final key = GlobalKey<State<NaverMapAdapter>>();
    final controller = _BlockingController();

    await tester.pumpWidget(_adapter(key, 'a'));
    (key.currentState! as dynamic).debugControllerForTest = controller;

    await tester.pumpWidget(_adapter(key, 'b'));
    await tester.pump();
    await tester.pumpWidget(_adapter(key, 'c'));
    await tester.pump();

    expect(controller.maxInFlight, 1);

    while (controller.gates.isNotEmpty) {
      controller.gates.removeAt(0).complete();
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
