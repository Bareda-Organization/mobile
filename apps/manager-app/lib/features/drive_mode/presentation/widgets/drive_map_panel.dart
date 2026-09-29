import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/core/map/map_surface.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

/// 운행 화면 가운데 지도(M-08·M-09 "노선", R32 M1) — 확정 노선의 도로 경로 · 승하차지 핀 ·
/// 현재 버스 위치를 한 화면에 보인다. 노선은 §4.3 [routeProvider] 를 그대로 쓰고
/// (노선 지도 화면과 같은 값), 버스 위치는 기사 단말이 스스로 잰 좌표 [busPosition] 이다.
class DriveMapPanel extends ConsumerWidget {
  const DriveMapPanel({required this.height, this.busPosition, super.key});

  /// 지도 면의 높이 — 화면 비율로 정해 도착·종료 대형 버튼을 밀어내지 않는다.
  final double height;

  /// 기사 단말이 마지막으로 잰 좌표. 아직 못 쟀으면 `null` — 버스 마커를 지어내지 않는다.
  final ({double lat, double lng})? busPosition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(routeProvider);
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: route.when(
          loading: () => const ColoredBox(
            color: Colors.black12,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => _Notice(
            message: '노선을 불러오지 못했습니다',
            action: TextButton(
              onPressed: () => ref.invalidate(routeProvider),
              child: const Text('다시 시도'),
            ),
          ),
          data: (route) => route.stops.isEmpty
              ? const _Notice(message: '표시할 승하차지가 없습니다')
              : _buildMap(route),
        ),
      ),
    );
  }

  Widget _buildMap(RouteResponse route) {
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

/// 지도를 그릴 수 없을 때 지도 자리에 넣는 한 줄 안내.
class _Notice extends StatelessWidget {
  const _Notice({required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Text(message), ?action],
        ),
      ),
    );
  }
}
