import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/map/frame_move_selector.dart';
import 'package:parent_app/core/map/marker_motion_controller.dart';

/// R46 C(D #11) — 프레임마다 `setPosition` 을 부를 마커는 보간 중인(움직이는) 마커뿐이다.
/// 정차지처럼 좌표를 한 번만 받은 마커는 호출 0.
void main() {
  final t0 = DateTime(2026, 10, 1, 8);

  ({Map<String, MarkerMotionController> motions, DateTime end}) fixture() {
    final bus = MarkerMotionController()
      ..onCoordinateReceived((lat: 37.5, lng: 127.0), t0)
      ..onCoordinateReceived(
        (lat: 37.6, lng: 127.1),
        t0.add(const Duration(seconds: 2)),
      );
    final stop = MarkerMotionController()
      ..onCoordinateReceived((lat: 37.55, lng: 127.05), t0);
    return (
      motions: {'bus': bus, 'stop-1': stop, 'stop-2': stop},
      end: t0.add(const Duration(seconds: 4)),
    );
  }

  test('보간 중인 버스만 고르고 정차지는 고르지 않는다', () {
    final f = fixture();
    final selector = FrameMoveSelector();

    final ids = selector.select(
      f.motions,
      t0.add(const Duration(seconds: 3)),
    );

    expect(ids, ['bus']);
  });

  test('보간이 끝난 첫 프레임에는 마지막 자리에 놓기 위해 한 번 더 고르고 그다음은 고르지 않는다', () {
    final f = fixture();
    final selector = FrameMoveSelector()
      ..select(f.motions, t0.add(const Duration(seconds: 3)));
    expect(selector.select(f.motions, f.end), ['bus']);
    expect(
      selector.select(f.motions, f.end.add(const Duration(seconds: 1))),
      isEmpty,
    );
  });
}
