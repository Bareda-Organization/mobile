import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:manager_app/core/map/map_surface.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';

/// 노선 항목 → 마커. 강제 경유 지점(`is_waypoint`)은 번호 없는 waypoint
/// 마커이고, 승하차지 번호는 **경유 지점을 뺀 순번**으로 다시 매긴다
/// (`Ruling 400`) — 서버 `seq` 는 경유 지점 자리를 비운 채 1·3·4 로 오는데
/// 명단(§4.2)은 경유 지점을 싣지 않으므로(`Ruling 398`) 서버 값을 그대로 쓰면
/// 지도와 명단 번호가 어긋난다. 마커는 받은 순서대로 낸다.
List<MapMarker> _stopMarkersOf(List<RouteStop> stops) {
  final ordered = [...stops]..sort((a, b) => a.seq.compareTo(b.seq));
  final orderOf = <String, int>{};
  for (final stop in ordered) {
    if (!stop.isWaypoint) orderOf[stop.stopId] = orderOf.length + 1;
  }
  return [
    for (final stop in stops)
      if (stop.isWaypoint)
        MapMarker(
          id: 'waypoint-${stop.stopId}',
          lat: stop.lat,
          lng: stop.lng,
          kind: MapMarkerKind.waypoint,
        )
      else
        MapMarker(
          id: stop.stopId,
          lat: stop.lat,
          lng: stop.lng,
          kind: MapMarkerKind.stop,
          seq: orderOf[stop.stopId],
          skipped: stop.change == RouteStopChange.skipped,
        ),
  ];
}

/// 확정 노선(§4.3)을 그리는 지도 면 — 도로 경로선 · 승하차지 핀 · (있으면) 기사 단말이 잰 버스 위치
/// · 근사 경로 안내. 운행 화면 가운데 패널(`DriveMapPanel`)과 노선 지도 화면(`RouteMapScreen`)이
/// **같은 지도를 두 벌 두지 않고** 이 위젯 하나를 쓴다(F06-11).
class RouteMapView extends StatelessWidget {
  const new({
    required this.route,
    this.busPosition,
    this.onAuthFailed,
    super.key,
  });

  final RouteResponse route;

  /// 기사 단말이 마지막으로 잰 좌표. 아직 못 쟀으면 `null` — 버스 마커를 지어내지 않는다.
  final ({double lat, double lng})? busPosition;

  /// 지도 SDK 인증 실패 콜백 — 호출부가 안내 문구를 정한다.
  final MapAuthFailedCallback? onAuthFailed;

  @override
  Widget build(BuildContext context) {
    // 도로 경로는 2점 이상이어야 선이 된다 — 없거나 비었으면 핀과 버스만 보인다.
    final hasPath = route.roadPath.length >= 2;
    final anchor = route.currentStop ?? route.nextStop ?? route.stops.first;
    final bus = busPosition;
    return Stack(
      children: [
        Positioned.fill(
          child: MapSurface(
            camera: MapCamera(lat: anchor.lat, lng: anchor.lng, zoom: 14),
            fitToContent: true,
            onAuthFailed: onAuthFailed,
            markers: [
              ..._stopMarkersOf(route.stops),
              if (bus != null)
                MapMarker(
                  id: 'bus',
                  lat: bus.lat,
                  lng: bus.lng,
                  kind: MapMarkerKind.bus,
                ),
            ],
            polylines: [
              if (hasPath) MapPolyline(id: 'road', points: route.roadPath),
            ],
          ),
        ),
        // 직선 근사를 실제 도로로 오인하지 않게 알린다(Ruling 309).
        if (hasPath && route.fallbackUsed)
          const Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: AlertBanner(
              tone: AlertTone.info,
              body: '근사 경로 — 실제 도로와 다를 수 있습니다',
            ),
          ),
      ],
    );
  }
}
