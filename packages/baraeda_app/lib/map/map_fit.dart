/// 카메라 맞춤 — 맞출 대상(마커 · 선)과 사각형을 정한다. SDK 를 모르는 순수 계산이다.
library;

import 'dart:math' as math;

import 'package:baraeda_app/map/map_models.dart';

/// [markers]·[polylines] 의 모든 점을 감싸는 사각형. 점이 하나도 없으면 `null`.
MapBounds? contentBounds(
  Iterable<MapMarker> markers,
  Iterable<MapPolyline> polylines,
) {
  final points = <({double lat, double lng})>[
    for (final marker in markers) (lat: marker.lat, lng: marker.lng),
    for (final line in polylines) ...line.points,
  ];
  if (points.isEmpty) return null;
  var south = points.first.lat;
  var north = south;
  var west = points.first.lng;
  var east = west;
  for (final point in points) {
    if (point.lat < south) south = point.lat;
    if (point.lat > north) north = point.lat;
    if (point.lng < west) west = point.lng;
    if (point.lng > east) east = point.lng;
  }
  return MapBounds(south: south, west: west, north: north, east: east);
}

/// 매니저 앱이 버스를 카메라 맞춤에 넣는 거리 — 노선 사각형을 이만큼(약 2km) 넓힌 범위 안의 버스만 넣는다.
/// 이보다 멀면 화면이 버스까지 넓어져 노선이 점처럼 작아지므로 맞춤 대상에서 뺀다.
const double busFitMarginMeters = 2000;

/// 위도 1도의 길이(미터). 경도 1도의 길이는 여기에 `cos(위도)` 를 곱한다.
const double _metersPerDegreeLatitude = 111320;

/// 카메라 맞춤 결과 — 맞출 사각형과 그 안에 넣은 마커 id · 선의 모양 키.
class MapFit {
  const new({
    required this.bounds,
    required this.markerIds,
    this.polylineKeys = const [],
  });

  final MapBounds bounds;

  /// 사각형에 넣은 마커의 id. 이 집합이 달라질 때만 카메라를 다시 맞춘다 — 버스가 노선 근처로
  /// 들어와 포함 여부가 바뀌면 id 에 `bus` 가 생겨 다시 맞춘다.
  final Set<String> markerIds;

  /// 사각형에 넣은 선의 `MapPolyline.lookKey` — 도로 경로가 뒤늦게 도착하거나 바뀌면 사각형이 달라지므로 서명에
  /// 넣는다.
  final List<String> polylineKeys;

  /// [markerIds] 를 정렬해 이은 값 + [polylineKeys] — 어댑터가 "지난번 맞춘 것과 같은가" 를 비교한다.
  String get signature =>
      '${(markerIds.toList()..sort()).join(',')}|${polylineKeys.join(',')}';
}

/// 카메라를 맞출 대상을 정한다 — 노선(버스가 아닌 마커 + [polylines])이 기준이다.
///
/// [busMarginMeters] 가 `null` 이면 버스를 맞춤에서 뺀다(달리는 중에는 카메라가 버스를 따라가고 맞춤은 버스가
/// 없는 화면에서만 쓴다) — 노선이 없으면 맞출 대상이 없다. 값이 있으면 버스 마커를 노선 사각형을 그만큼 넓힌
/// 범위 안일 때만 넣고, 노선이 없으면(점이 하나도 없으면) 있는 것을 전부 맞춘다. 맞출 점이 없으면 `null`.
MapFit? cameraFit(
  Iterable<MapMarker> markers,
  Iterable<MapPolyline> polylines, {
  required double? busMarginMeters,
}) {
  final routeMarkers = [
    for (final marker in markers)
      if (marker.kind != MapMarkerKind.bus) marker,
  ];
  final polylineKeys = [for (final line in polylines) line.lookKey];
  final route = contentBounds(routeMarkers, polylines);
  if (route == null) {
    if (busMarginMeters == null) return null;
    final all = contentBounds(markers, polylines);
    if (all == null) return null;
    return MapFit(
      bounds: all,
      markerIds: {for (final m in markers) m.id},
      polylineKeys: polylineKeys,
    );
  }
  final nearBuses = [
    if (busMarginMeters != null)
      for (final marker in markers)
        if (marker.kind == MapMarkerKind.bus &&
            _isNear(route, marker, busMarginMeters))
          marker,
  ];
  final included = [...routeMarkers, ...nearBuses];
  return MapFit(
    bounds: contentBounds(included, polylines)!,
    markerIds: {for (final m in included) m.id},
    polylineKeys: polylineKeys,
  );
}

/// [marker] 가 [route] 를 [marginMeters] 넓힌 사각형 안인가 — 경도는 그 위도의 실제 거리로 잰다.
bool _isNear(MapBounds route, MapMarker marker, double marginMeters) {
  final latMargin = marginMeters / _metersPerDegreeLatitude;
  final midLat = (route.south + route.north) / 2;
  final lngMargin =
      marginMeters /
      (_metersPerDegreeLatitude * math.cos(midLat * math.pi / 180));
  return marker.lat >= route.south - latMargin &&
      marker.lat <= route.north + latMargin &&
      marker.lng >= route.west - lngMargin &&
      marker.lng <= route.east + lngMargin;
}
