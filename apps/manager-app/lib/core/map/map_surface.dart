/// 지도 SDK 포트 — 화면 코드가 지켜야 할 유일한 규칙은 이 파일만 import 하는
/// 것이다(F4-B 1단계 공통 규칙 §2). `NaverMap` · `NMarker` · `NLatLng` 같은
/// SDK 타입은 `naver/naver_map_adapter.dart` 뒤에 숨는다 — 지도 SDK 를
/// 교체해도 화면은 이 파일의 타입만 알면 된다.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:manager_app/core/map/naver/naver_map_adapter.dart';

/// 지도 카메라(중심 좌표·확대 수준).
class MapCamera {
  const MapCamera({required this.lat, required this.lng, required this.zoom});

  final double lat;
  final double lng;
  final double zoom;
}

/// 마커의 종류 — 아이콘·색상 등 실제 표현은 어댑터가 정한다. 화면은 어떤
/// 대상을 찍는지만 밝힌다.
enum MapMarkerKind {
  /// 운행 중인 버스의 현재 위치.
  bus,

  /// 승하차지(정류장).
  stop,

  /// 학생의 위치(승하차 지점과 별도로 찍어야 할 때).
  student,
}

/// 지도 위에 놓일 마커 하나.
class MapMarker {
  const MapMarker({
    required this.id,
    required this.lat,
    required this.lng,
    required this.kind,
    this.seq,
  });

  final String id;
  final double lat;
  final double lng;
  final MapMarkerKind kind;

  /// 정차지 순번 — [MapMarkerKind.stop] 핀 안에 그린다(2026-09-23 사용자 지시).
  final int? seq;
}

/// 지도 위에 그릴 선 하나(예: 확정 노선의 도로 경로). 점은 순서대로 이어진다.
class MapPolyline {
  const MapPolyline({required this.id, required this.points});

  final String id;
  final List<({double lat, double lng})> points;
}

/// 마커·선이 전부 들어오는 최소 사각형 — 카메라를 내용에 맞출 때 쓴다.
class MapBounds {
  const MapBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  /// 점이 하나뿐이라 넓이가 0 인 경우 — 어댑터가 확대 수준을 따로 정한다.
  bool get isPoint => south == north && west == east;
}

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

/// 버스를 카메라 맞춤에 넣는 거리 — 노선 사각형을 이만큼(약 2km) 넓힌 범위 안의 버스만 넣는다.
/// 이보다 멀면 화면이 버스까지 넓어져 노선이 점처럼 작아지므로 맞춤 대상에서 뺀다.
const double busFitMarginMeters = 2000;

/// 위도 1도의 길이(미터). 경도 1도의 길이는 여기에 `cos(위도)` 를 곱한다.
const double _metersPerDegreeLatitude = 111320;

/// 카메라 맞춤 결과 — 맞출 사각형과 그 안에 넣은 마커 id.
class MapFit {
  const MapFit({required this.bounds, required this.markerIds});

  final MapBounds bounds;

  /// 사각형에 넣은 마커의 id. 이 집합이 달라질 때만 카메라를 다시 맞춘다 — 버스가 노선 근처로
  /// 들어와 포함 여부가 바뀌면 id 에 `bus` 가 생겨 다시 맞춘다.
  final Set<String> markerIds;

  /// [markerIds] 를 정렬해 이은 값 — 어댑터가 "지난번 맞춘 것과 같은가" 를 비교한다.
  String get signature => (markerIds.toList()..sort()).join(',');
}

/// 카메라를 맞출 대상을 정한다 — 노선(버스가 아닌 마커 + [polylines])이 기준이고, 버스 마커는
/// 노선 사각형을 [busFitMarginMeters] 넓힌 범위 안일 때만 넣는다. 노선이 없으면(점이 하나도 없으면)
/// 있는 것을 전부 맞춘다. 맞출 점이 없으면 `null`.
MapFit? cameraFit(
  Iterable<MapMarker> markers,
  Iterable<MapPolyline> polylines,
) {
  final routeMarkers = [
    for (final marker in markers)
      if (marker.kind != MapMarkerKind.bus) marker,
  ];
  final route = contentBounds(routeMarkers, polylines);
  if (route == null) {
    final all = contentBounds(markers, polylines);
    if (all == null) return null;
    return MapFit(bounds: all, markerIds: {for (final m in markers) m.id});
  }
  final nearBuses = [
    for (final marker in markers)
      if (marker.kind == MapMarkerKind.bus && _isNear(route, marker)) marker,
  ];
  final included = [...routeMarkers, ...nearBuses];
  return MapFit(
    bounds: contentBounds(included, polylines)!,
    markerIds: {for (final m in included) m.id},
  );
}

/// [marker] 가 [route] 를 [busFitMarginMeters] 넓힌 사각형 안인가 — 경도는 그 위도의 실제 거리로 잰다.
bool _isNear(MapBounds route, MapMarker marker) {
  const latMargin = busFitMarginMeters / _metersPerDegreeLatitude;
  final midLat = (route.south + route.north) / 2;
  final lngMargin =
      busFitMarginMeters /
      (_metersPerDegreeLatitude * math.cos(midLat * math.pi / 180));
  return marker.lat >= route.south - latMargin &&
      marker.lat <= route.north + latMargin &&
      marker.lng >= route.west - lngMargin &&
      marker.lng <= route.east + lngMargin;
}

/// 지도 준비 완료 콜백 — SDK 가 타일을 그릴 준비를 마치면 호출된다.
typedef MapReadyCallback = void Function();

/// 지도 인증 실패 콜백. SDK 예외를 그대로 넘기되(예외 자체를 삼키거나
/// 다른 값으로 바꾸지 않는다), 화면 코드가 SDK 예외 타입을 몰라도 되도록
/// [Object] 로 받는다.
typedef MapAuthFailedCallback = void Function(Object exception);

/// 화면이 지도 SDK 를 직접 알지 못하게 감싸는 위젯.
///
/// 실제 렌더링·마커 배치는 [NaverMapAdapter] 가 맡는다. 이 클래스는 그
/// 어댑터를 감싸는 얇은 위임일 뿐이며, SDK import 는 이 파일에 없다.
class MapSurface extends StatelessWidget {
  const MapSurface({
    required this.camera,
    super.key,
    this.markers = const [],
    this.polylines = const [],
    this.fitToContent = false,
    this.onReady,
    this.onAuthFailed,
  });

  /// 초기 카메라 위치. 마커 목록이 바뀌어도 카메라를 자동으로 다시
  /// 맞추지 않는다 — 필요하면 호출부가 새 [MapCamera] 를 내려준다.
  final MapCamera camera;

  /// 지도 위에 찍을 마커 목록.
  final List<MapMarker> markers;

  /// 지도 위에 그릴 선 목록(도로 경로 등).
  final List<MapPolyline> polylines;

  /// `true` 면 카메라를 노선(승하차지 핀·도로 경로)이 전부 보이게 맞춘다 — 지도가 준비된 직후와,
  /// 맞춤 대상이 바뀔 때 다시 맞춘다. 버스 마커는 노선 사각형을 약 2km 넓힌 범위 안일 때만 맞춤에
  /// 넣고(`cameraFit`), 버스가 그 범위를 드나들어 포함 여부가 바뀌면 다시 맞춘다. 좌표만 바뀔 때는
  /// 맞추지 않는다(사용자가 옮겨 둔 화면을 빼앗지 않는다). [camera] 는 맞추기 전 초기 위치가 된다.
  final bool fitToContent;

  /// 지도 준비 완료 콜백.
  final MapReadyCallback? onReady;

  /// 인증 실패 콜백.
  final MapAuthFailedCallback? onAuthFailed;

  @override
  Widget build(BuildContext context) {
    return NaverMapAdapter(
      camera: camera,
      markers: markers,
      polylines: polylines,
      fitToContent: fitToContent,
      onReady: onReady,
      onAuthFailed: onAuthFailed,
    );
  }
}
