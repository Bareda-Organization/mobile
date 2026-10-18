import 'package:baraeda_app/baraeda_app.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:manager_app/core/map/stop_pin.dart';
import 'package:manager_app/core/map/waypoint_chip.dart';

/// 매니저 앱의 지도 설정 — 모든 지도 화면이 같게 쓴다.
///
/// 순번 물방울 핀 · "경유" 칩 · 파란 노선 · 버스는 노선 2km 안일 때만 맞춤에
/// 넣는다. 좌표가 오는 즉시 마커를 옮기고 카메라는 초기 위치로만 쓴다.
const managerMapOptions = MapSurfaceOptions(
  markerIcon: _markerIcon,
  fitBusMarginMeters: busFitMarginMeters,
  placeholderBuilder: _placeholder,
);

/// 승하차지는 순번 핀(끝이 좌표), 경유 지점은 칩(가운데가 좌표)이다.
MapMarkerIcon? _markerIcon(MapMarker marker) => switch (marker.kind) {
  MapMarkerKind.stop => MapMarkerIcon(
    widget: StopPin(seq: marker.seq, skipped: marker.skipped),
    size: StopPin.size,
  ),
  MapMarkerKind.waypoint => const MapMarkerIcon(
    widget: WaypointChip(),
    size: WaypointChip.size,
    centered: true,
  ),
  MapMarkerKind.bus || MapMarkerKind.student => null,
};

/// 초기화 중에는 스피너, 실패하면 문구 — "데이터 없음" 과 "지도 인증 실패" 를 구분한다.
Widget _placeholder(BuildContext context, Object? error) {
  return ColoredBox(
    color: Colors.black12,
    child: Center(
      child: error == null
          ? const CircularProgressIndicator()
          : const WordWrapText('지도를 불러오지 못했어요'),
    ),
  );
}
