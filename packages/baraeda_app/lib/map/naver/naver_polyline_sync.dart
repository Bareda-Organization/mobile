import 'package:baraeda_app/map/map_surface.dart';
import 'package:baraeda_app/map/naver/naver_overlay_factory.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

/// 지도 위에 올라가 있는 선을 기억하고, 새 선 목록과 비교해 지울 것은 지우고 더할 것은 모은다.
class NaverPolylineSync {
  /// 지금 지도 위에 올라가 있는 선의 모양 키(id 별) — 바뀌면 지우고 다시 그린다.
  final Map<String, String> _linesById = {};

  /// 선을 지도에 맞춘다 — 없어진 것은 지우고, 모양이 달라진 것은 지우고 다시 그리고, 새것은 [toAdd] 에 더한다.
  /// 테두리 색이 있으면 선마다 아래에 테두리 선을 한 겹 더 깐다(지도 길 위에서도 선이 보이게). 화면은 선 1개만 안다.
  Future<void> sync(
    NaverMapController controller,
    List<MapPolyline> lines,
    NaverOverlayFactory overlays,
    Set<NAddableOverlay> toAdd,
  ) async {
    final hasHalo = overlays.options.polylineStyle.haloColor != null;
    final incoming = {for (final line in lines) line.id: line};
    for (final id in _linesById.keys.toList()) {
      if (incoming[id]?.lookKey == _linesById[id]) continue;
      _linesById.remove(id);
      if (hasHalo) {
        await controller.deleteOverlay(
          NaverOverlayFactory.polylineInfo('$id#halo'),
        );
      }
      await controller.deleteOverlay(NaverOverlayFactory.polylineInfo(id));
    }
    for (final line in incoming.values) {
      if (_linesById.containsKey(line.id)) continue;
      _linesById[line.id] = line.lookKey;
      if (hasHalo) toAdd.add(overlays.polyline(line, halo: true));
      toAdd.add(overlays.polyline(line, halo: false));
    }
  }
}
