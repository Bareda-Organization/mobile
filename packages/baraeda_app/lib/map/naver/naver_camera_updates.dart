import 'package:baraeda_app/map/map_surface.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

/// 지도 계약의 카메라 · 맞춤 값을 SDK 카메라 이동으로 바꾼다.
abstract final class NaverCameraUpdates {
  /// 카메라가 새 좌표로 옮겨 가는 시간 — 마커 보간 간격(위치 송신 주기 약 2초)보다 살짝 짧게 둬 다음 좌표 전에 끝낸다.
  static const followDuration = Duration(milliseconds: 1800);

  /// 두 카메라가 같은 좌표 · 확대인가.
  static bool sameCamera(MapCamera a, MapCamera b) =>
      a.lat == b.lat && a.lng == b.lng && a.zoom == b.zoom;

  /// [camera] 로 [followDuration] 동안 선형으로 따라가는 이동.
  ///
  /// 마커는 새 좌표까지 약 2초에 걸쳐 미끄러진다 — 카메라가 즉시 옮겨 가면 마커가 매번 중앙에서 튕겨 나갔다
  /// 돌아오므로, 같은 속도로 따라가게 천천히 옮긴다.
  static NCameraUpdate follow(MapCamera camera) =>
      NCameraUpdate.scrollAndZoomTo(
        target: NLatLng(camera.lat, camera.lng),
        zoom: camera.zoom,
      )..setAnimation(
        animation: NCameraAnimation.linear,
        duration: followDuration,
      );

  /// 맞춤 대상 [fit] 이 한 점이면 그 점으로 [zoom] 만큼 확대하고, 아니면 [padding] 을 둔 영역에 맞춘다.
  static NCameraUpdate fit(
    MapFit fit, {
    required double zoom,
    required EdgeInsets padding,
  }) {
    final bounds = fit.bounds;
    if (bounds.isPoint) {
      return NCameraUpdate.scrollAndZoomTo(
        target: NLatLng(bounds.south, bounds.west),
        zoom: zoom,
      );
    }
    return NCameraUpdate.fitBounds(
      NLatLngBounds(
        southWest: NLatLng(bounds.south, bounds.west),
        northEast: NLatLng(bounds.north, bounds.east),
      ),
      padding: padding,
    );
  }
}
