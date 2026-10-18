import 'package:baraeda_app/baraeda_app.dart';
import 'package:flutter/material.dart';
import 'package:parent_app/core/map/stop_number_pin.dart';

/// 학부모 앱의 지도 설정 — 모든 지도 화면이 같게 쓴다.
///
/// 번호 원형 핀 · 초록 노선(지나온 길 회색, 흰 테두리) · 버스는 맞춤에서 뺀다.
/// 마커는 수신 간격만큼 부드럽게 움직이고 카메라는 새 중심을 따라간다.
const parentMapOptions = MapSurfaceOptions(
  markerIcon: _markerIcon,
  polylineStyle: MapPolylineStyle(
    color: Color(0xFF1F5C4D),
    passedColor: Color(0xFF8F9995),
    haloColor: Colors.white,
  ),
  smoothMarkerMotion: true,
  followCameraChanges: true,
);

/// 번호가 있는 마커는 번호 원형 핀이다 — 동그라미라 가운데가 좌표에 온다.
MapMarkerIcon? _markerIcon(MapMarker marker) {
  final seq = marker.seq;
  if (seq == null) return null;
  return MapMarkerIcon(
    widget: StopNumberPin(seq: seq, mine: marker.mine),
    size: StopNumberPin.sizeOf(mine: marker.mine),
    centered: true,
  );
}
