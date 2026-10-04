import 'package:parent_app/core/map/map_surface.dart';
import 'package:parent_app/core/routes/domain/route_detail.dart';

/// §3.10 노선을 지도에 얹을 마커와 선으로 바꾼 것 — 홈 미리보기와 실시간 위치(운행 중 · 종료)가 같이 쓴다.
///
/// **표시 범위(승차지 이전 2개 · 승차지 · 하차지, P-08)는 서버가 이미 좁혀 보낸다.** 이 클래스는 응답에 있는
/// 승하차지만 그리고, 없는 승하차지의 위치를 만들어 내지 않는다(`Ruling 831` — 다른 아이의 승하차지 위치를 덜 드러낸다).
class RouteMapOverlay {
  const new({required this.markers, required this.polylines});

  /// [route] 의 승하차지마다 번호 마커 하나, 그 사이를 잇는 선 하나.
  ///
  /// - 번호는 승하차지의 **실제 `seq`** 다 — 목록 순번이 아니다(표시 범위가 3~5번이면 3 · 4 · 5).
  /// - **학원 항목**(`stopId` 가 `null` — 등원이면 마지막 · 하원이면 맨 앞이고 `seq` 가 0)에는
  ///   번호를 달지 않고 글자 "학원" 만 단다. 경로선의 끝(등원) · 시작(하원) 점으로는 그대로 쓴다.
  /// - 선은 `road_path` 가 2점 이상이면 그 도로 경로, 아니면 좌표가 있는 표시 승하차지를 이은 **점선**이다
  ///   (확정 전이거나 도로 좌표가 빈 옛 버전 — 실제 도로가 아니라는 표시).
  /// - [ended] 는 운행이 끝난 뒤 — 선을 "지나온 구간" 색으로 그린다.
  /// - [markNext] 는 운행 중 — 아직 안 지난 첫 승하차지를 "다음" 모양으로
  ///   그린다. 도착 예정 시각이나 "몇 곳 전"이 아니라 순서만 말한다(C-08).
  /// - 좌표가 없는 승하차지(학원 항목이 `lat`·`lng` 를 못 가질 수 있다)는 마커도 점선 꼭짓점도 만들지 않는다.
  ///
  /// [idPrefix] 는 같은 마커·선을 다음 갱신에서도 알아보게 하는 화면별 접두어다.
  factory of(
    RouteDetail route, {
    required String idPrefix,
    bool ended = false,
    bool markNext = false,
  }) {
    final located = [
      for (final stop in route.stops)
        if (stop.lat != null && stop.lng != null) stop,
    ];
    // "다음 곳" 은 실제 승하차지 중에서만 고른다 — 하원은 학원이 맨 앞이라 거르지 않으면 학원이 "다음 곳" 을 가로챈다.
    final nextStopId = markNext
        ? located
              .where((stop) => stop.stopId != null && stop.arrivedAt == null)
              .firstOrNull
              ?.stopId
        : null;

    final markers = [
      for (final stop in located)
        if (stop.stopId == null)
          MapMarker(
            id: '$idPrefix-academy',
            lat: stop.lat!,
            lng: stop.lng!,
            kind: MapMarkerKind.stop,
            label: _academyLabel,
          )
        else
          MapMarker(
            id: '$idPrefix-stop-${stop.stopId}',
            lat: stop.lat!,
            lng: stop.lng!,
            kind: MapMarkerKind.stop,
            seq: stop.seq,
            stopState: stop.arrivedAt != null
                ? MapStopState.passed
                : (stop.stopId == nextStopId
                      ? MapStopState.next
                      : MapStopState.upcoming),
            mine: stop.stopId == route.myStopId,
            label: stop.stopId == route.myStopId ? _myStopLabel : null,
          ),
    ];

    final hasRoad = route.roadPath.length >= 2;
    final points = hasRoad
        ? route.roadPath
        : [for (final stop in located) (lat: stop.lat!, lng: stop.lng!)];
    final polylines = [
      if (points.length >= 2)
        MapPolyline(
          id: '$idPrefix-route',
          points: points,
          dashed: !hasRoad,
          passed: ended,
        ),
    ];
    return RouteMapOverlay(markers: markers, polylines: polylines);
  }

  /// 내 승하차지에 다는 이름표 — 시트의 "내 승하차지" 칸과 같은 말이다.
  static const _myStopLabel = '내 승하차지';

  /// 학원 항목에 다는 글자 — 등원이면 도착 · 하원이면 출발 지점이다.
  static const _academyLabel = '학원';

  final List<MapMarker> markers;
  final List<MapPolyline> polylines;

  /// 그릴 것이 하나도 없다 — 이때 지도는 노선 없이 버스만 그린다(또는 지도를
  /// 그리지 않는다).
  bool get isEmpty => markers.isEmpty && polylines.isEmpty;

  /// 지도가 처음 비출 자리 — 노선의 첫 점. 버스가 없는 화면(종료)이 `fitToContent`
  /// 로 노선 전체에 맞추기 전의 초기 위치로 쓴다. 그릴 것이 없으면 `null`.
  MapCamera? get start {
    final first = markers.firstOrNull;
    if (first != null) return MapCamera(lat: first.lat, lng: first.lng);
    final point = polylines.firstOrNull?.points.first;
    return point == null ? null : MapCamera(lat: point.lat, lng: point.lng);
  }
}
