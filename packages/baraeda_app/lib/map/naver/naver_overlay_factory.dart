import 'package:baraeda_app/map/map_surface.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

/// 아이콘이 없는 승하차지 핀의 색 — 디자인 시스템의 `statusMoving`(앰버)과 같은 계열로,
/// 버스 핀(기본 초록)과 갈린다. 지도 어댑터는 `BuildContext` 없이 마커를 만들어
/// 의미 색을 못 읽어 원시 팔레트를 가리킨다.
const Color _stopMarkerTint = BaraedaPalette.amber600;

/// 지도 계약의 마커 · 선을 SDK 오버레이로 바꾸는 공장 —
/// 앱이 정한 [MapSurfaceOptions] 의 아이콘 · 선 모양을 쓴다.
class NaverOverlayFactory {
  /// [options] 의 마커 아이콘 · 선 모양으로 오버레이를 만든다.
  const new(this.options);

  final MapSurfaceOptions options;

  /// 마커 한 개를 SDK 마커로 만든다. 앱이 아이콘을 주면 그 위젯을 이미지로 굳혀 쓰고, 없으면 기본 핀에 글자를 단다.
  Future<NMarker> marker(MapMarker marker, BuildContext context) async {
    final position = NLatLng(marker.lat, marker.lng);
    final icon = options.markerIcon?.call(marker);
    if (icon != null) {
      final image = await NOverlayImage.fromWidget(
        widget: icon.widget,
        size: icon.size,
        context: context,
      );
      return NMarker(
        id: marker.id,
        position: position,
        icon: image,
        // 동그라미 · 칩은 기준점이 가운데다 — 핀 끝이 좌표에 오는 물방울과 다르다.
        anchor: icon.centered ? NPoint.relativeCenter : NMarker.defaultAnchor,
        // 아이콘이 종류를 말하므로 글자는 이름표가 있을 때만 붙인다.
        caption: marker.label == null
            ? null
            : NOverlayCaption(text: marker.label!),
        // 왼쪽이 먼저이고, 다른 오버레이와 겹치면 위 · 오른쪽 순으로 옮긴다.
        captionAligns: const [NAlign.left, NAlign.top, NAlign.right],
      );
    }
    return NMarker(
      id: marker.id,
      position: position,
      caption: NOverlayCaption(text: marker.label ?? _captionFor(marker.kind)),
      // 기본 핀이 전부 같은 초록이라 버스와 승하차지가 글자 없이는 안 갈렸다.
      // 생성할 때 한 번만 지정한다 — 만든 뒤 바꾸지 않아 네이티브 호출이 늘지 않는다.
      iconTintColor: marker.kind == MapMarkerKind.stop
          ? _stopMarkerTint
          : Colors.transparent,
    );
  }

  /// 선 색은 앱이 정한다 — 테두리 선은 [MapPolylineStyle.haloColor] 가 있을 때만 깐다.
  NPolylineOverlay polyline(MapPolyline line, {required bool halo}) {
    final style = options.polylineStyle;
    final mainColor = line.passed
        ? (style.passedColor ?? style.color)
        : style.color;
    return NPolylineOverlay(
      id: halo ? '${line.id}#halo' : line.id,
      coords: [for (final p in line.points) NLatLng(p.lat, p.lng)],
      color: halo ? style.haloColor! : mainColor,
      width: halo ? style.haloWidth : style.width,
      lineCap: NLineCap.round,
      lineJoin: NLineJoin.round,
      // 점선은 도로가 아니라 승하차지끼리 곧게 이은 선이다 — 테두리는 실선으로 둬 길 위에서 끊겨 보이지 않게 한다.
      pattern: line.dashed && !halo ? const [8, 8] : const [],
    );
  }

  /// 지울 선 오버레이를 가리키는 식별 정보.
  static NOverlayInfo polylineInfo(String id) =>
      NOverlayInfo(type: NOverlayType.polylineOverlay, id: id);

  static String _captionFor(MapMarkerKind kind) => switch (kind) {
    MapMarkerKind.bus => '버스',
    MapMarkerKind.stop => '승하차지',
    MapMarkerKind.student => '학생',
    MapMarkerKind.waypoint => '경유',
  };
}
