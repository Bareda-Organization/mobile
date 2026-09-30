import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:manager_app/core/map/map_surface.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';

/// 확정 노선(§4.3)을 그리는 지도 면 — 도로 경로선 · 승하차지 핀 · (있으면) 기사 단말이 잰 버스 위치
/// · 근사 경로 안내. 운행 화면 가운데 패널(`DriveMapPanel`)과 노선 지도 화면(`RouteMapScreen`)이
/// **같은 지도를 두 벌 두지 않고** 이 위젯 하나를 쓴다(F06-11).
class RouteMapView extends StatelessWidget {
  const RouteMapView({
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
              for (final stop in route.stops)
                MapMarker(
                  id: stop.stopId,
                  lat: stop.lat,
                  lng: stop.lng,
                  kind: MapMarkerKind.stop,
                  seq: stop.seq,
                ),
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
