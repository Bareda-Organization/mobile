/// 지도 화면 전체가 의존해야 하는 **유일한 공개 계약**이다.
///
/// **판단 근거 — 왜 포트 뒤에 두는가**: 지도 공급자(네이버 vs Tmap)는
/// 가격 정책에 따라 나중에 바뀔 수 있다(`IMPLEMENTATION_PLAN.md §8.3.1`).
/// 화면 코드가 `NaverMap`·`NMarker`·`NLatLng` 같은 SDK 타입을 직접 참조하면
/// 공급자를 바꿀 때 화면 20여 개를 전부 고쳐야 한다 — 이 파일과
/// `naver/` 하위 파일만 바뀌면 되도록, SDK 타입은 이 파일 바깥(화면 쪽)에
/// **한 줄도** 나타나지 않게 막는다. 그 경계는
/// `test/architecture/map_port_boundary_test.dart` 가 자동으로 검사한다.
///
/// 이 파일 자체는 `naver/naver_map_adapter.dart` 를 참조하지만, 그 파일
/// 안에서만 `package:flutter_naver_map` 을 쓰므로 경계 규칙을 어기지
/// 않는다 — "화면은 이 파일만 보고, 이 파일이 어댑터로 위임한다"가
/// 포트/어댑터 구조의 본래 모양이다.
library;

import 'package:flutter/widgets.dart';
import 'package:parent_app/core/map/naver/naver_map_adapter.dart';

/// 카메라(지도가 비추는 중심·확대 수준). 좌표계는 위경도(WGS84)를 가정한다.
class MapCamera {
  const new({required this.lat, required this.lng, this.zoom = 15});

  final double lat;
  final double lng;
  final double zoom;
}

/// 마커 한 개가 무엇을 가리키는지 — 공급자를 바꿔도 이 3종 분류는 그대로
/// 간다(외양만 어댑터가 새로 그린다).
enum MapMarkerKind { bus, stop, student }

/// 번호 마커(승하차지)가 지금 어떤 상태인가 — 모양(색·확인 표시)이 이 값으로 갈린다.
enum MapStopState {
  /// 아직 안 지난 곳.
  upcoming,

  /// 안 지난 곳 중 버스가 다음에 갈 곳 — 운행 중에만 쓴다(도착 예정 시각이 아니라 순서일 뿐이다, C-08).
  next,

  /// 이미 지난 곳(도착 처리 시각이 있다) — 확인 표시.
  passed,
}

/// 지도 위에 찍을 점 하나. `id` 는 같은 마커를 다음 갱신에서도 알아보기
/// 위한 값이라 화면마다 고유해야 한다(예: `'bus-$studentId'`).
class MapMarker {
  const new({
    required this.id,
    required this.lat,
    required this.lng,
    required this.kind,
    this.label,
    this.seq,
    this.stopState = MapStopState.upcoming,
    this.mine = false,
  });

  final String id;
  final double lat;
  final double lng;
  final MapMarkerKind kind;

  /// 마커 옆에 붙는 짧은 글자 — 없으면 종류별 기본 글자(`버스`·`승하차지`·`학생`)를 쓴다.
  /// 번호 마커(`seq` 가 있는 승하차지)는 핀이 종류를 말하므로 이 값이 있을 때만 글자를 붙인다.
  final String? label;

  /// 승하차지 번호 — **서버가 준 실제 순서(`seq`)** 다. 목록 순번이 아니다(표시 범위가 3~5번이면 3·4·5).
  /// 있으면 어댑터가 번호가 든 핀으로 그린다.
  final int? seq;

  /// 번호 마커의 지나간 정도.
  final MapStopState stopState;

  /// 내 승하차지 — 더 크게 · 둘레를 점선으로 강조한다.
  final bool mine;

  /// 아이콘 모양을 정하는 값의 묶음 — 이 값이 달라지면 어댑터가 마커 아이콘을 다시 만든다(좌표는 제외).
  /// 번호 · 지나감 · 내 승하차지가 운행 중에 바뀌어도 마커 id 는 그대로라, 좌표만 비교하면 옛 아이콘이 남는다.
  String get lookKey => '${kind.name}|$seq|${stopState.name}|$mine';
}

/// 지도 위에 그릴 선 하나(예: 확정 노선의 도로 경로). 점은 순서대로 이어진다.
///
/// ponytail: 매니저 앱 `core/map/map_surface.dart` 의 `MapPolyline` 과 같은 부품이다 — 공용 패키지로 올리는 일은
/// 이번 범위 밖이라 복제했다(두 앱 모두 `baraeda_ui` 가 아니라 앱 안에 지도 포트를 따로 둔다). 올릴 때 합친다.
class MapPolyline {
  const new({
    required this.id,
    required this.points,
    this.dashed = false,
    this.passed = false,
  });

  final String id;
  final List<({double lat, double lng})> points;

  /// 점선 — 도로 좌표가 없어 승하차지끼리 곧게 이은 경우(실제 도로가 아니다).
  final bool dashed;

  /// 지나온 구간 색(회색) — 운행이 끝난 뒤의 선.
  final bool passed;

  /// 같은 선인지 가르는 값 — 이 값이 달라지면 어댑터가 선을 지우고 다시 그린다.
  String get lookKey =>
      '$dashed|$passed|${Object.hashAll(points.map((p) => (p.lat, p.lng)))}';
}

/// 마커·선이 전부 들어오는 최소 사각형 — 카메라를 노선에 맞출 때 쓴다.
class MapBounds {
  const new({
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

/// 카메라를 맞출 대상의 사각형 — **버스가 아닌 마커**와 [polylines] 의 모든 점을 감싼다. 점이 없으면 `null`.
/// 버스는 넣지 않는다: 달리는 중에는 카메라가 버스를 따라가고, 맞춤은 버스가 없는 종료 화면에서만 쓴다.
MapBounds? contentBounds(
  Iterable<MapMarker> markers,
  Iterable<MapPolyline> polylines,
) {
  final points = <({double lat, double lng})>[
    for (final marker in markers)
      if (marker.kind != MapMarkerKind.bus) (lat: marker.lat, lng: marker.lng),
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

/// 화면이 실제로 그리는 지도 위젯. 내부 구현은 전부
/// `naver/naver_map_adapter.dart` 에 있다 — 이 클래스는 그 위임 하나만
/// 한다.
class MapSurface extends StatelessWidget {
  const new({
    required this.camera,
    super.key,
    this.markers = const [],
    this.polylines = const [],
    this.fitToContent = false,
    this.fitPadding = const EdgeInsets.all(48),
    this.onReady,
    this.onAuthFailed,
    this.onUserGesture,
  });

  final MapCamera camera;
  final List<MapMarker> markers;

  /// 지도 위에 그릴 선 목록(도로 경로 등).
  final List<MapPolyline> polylines;

  /// `true` 면 카메라를 노선(버스가 아닌 마커 · 선)이 전부 보이게 맞춘다 — 지도가 준비된 직후와 맞춤 대상이 바뀔 때만.
  /// 좌표만 바뀔 때는 맞추지 않는다(사용자가 옮겨 둔 화면을 빼앗지 않는다). [camera] 는 맞추기 전 초기 위치다.
  final bool fitToContent;

  /// [fitToContent] 로 맞출 때 노선 둘레에 비워 둘 여백 — 지도 위를 덮는 머리줄 · 아래 시트만큼 늘려 노선이 가려지지
  /// 않게 한다.
  final EdgeInsets fitPadding;

  /// 지도가 사용자 조작을 받을 수 있는 시점에 한 번 호출된다.
  final VoidCallback? onReady;

  /// SDK 인증 실패 시 호출된다. 원본 예외를 가공하지 않고 그대로 넘긴다
  /// (팀 공통 규칙 — 오류 분류는 호출부가 한다).
  final void Function(Object exception)? onAuthFailed;

  /// 사용자가 손으로 지도를 움직이거나 확대·축소했을 때 호출된다 — 코드가 카메라를 옮긴 경우는 부르지 않는다.
  final VoidCallback? onUserGesture;

  @override
  Widget build(BuildContext context) {
    return NaverMapAdapter(
      camera: camera,
      markers: markers,
      polylines: polylines,
      fitToContent: fitToContent,
      fitPadding: fitPadding,
      onReady: onReady,
      onAuthFailed: onAuthFailed,
      onUserGesture: onUserGesture,
    );
  }
}
