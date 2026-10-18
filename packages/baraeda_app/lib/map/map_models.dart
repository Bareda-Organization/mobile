/// 지도 화면이 주고받는 값 — 카메라 · 마커 · 선 · 사각형. 지도 SDK 타입은 하나도 없다.
///
/// 화면은 이 값과 `map_surface.dart` 의 `MapSurface` 만 안다. `NaverMap` · `NMarker` ·
/// `NLatLng` 같은
/// SDK 타입은 `naver/` 폴더 안에만 있어, 지도 공급자를 바꿀 때 화면을 고치지
/// 않는다(`map_sdk_boundary_test`).
library;

/// 지도 카메라(중심 좌표 · 확대 수준). 좌표계는 위경도(WGS84)다.
class MapCamera {
  const new({required this.lat, required this.lng, this.zoom = 15});

  final double lat;
  final double lng;
  final double zoom;
}

/// 마커가 가리키는 대상 — 아이콘 · 색 같은 실제 표현은 앱이 정한다(`MapSurfaceOptions.markerIcon`).
enum MapMarkerKind {
  /// 운행 중인 버스의 현재 위치.
  bus,

  /// 승하차지(정류장).
  stop,

  /// 학생의 위치(승하차 지점과 별도로 찍어야 할 때).
  student,

  /// 강제 경유 지점(`Ruling 400`) — 번호 없는 "경유" 칩. 태울 학생이 없는 지점이다.
  waypoint,
}

/// 지도 위에 찍을 점 하나. [id] 는 같은 마커를 다음 갱신에서도 알아보는 값이라 화면마다 고유해야 한다.
class MapMarker {
  const new({
    required this.id,
    required this.lat,
    required this.lng,
    required this.kind,
    this.label,
    this.seq,
    this.mine = false,
    this.skipped = false,
  });

  final String id;
  final double lat;
  final double lng;
  final MapMarkerKind kind;

  /// 마커 옆에 붙는 짧은 글자 — 없으면 종류별 기본 글자를 쓴다. 아이콘이 있는 마커는 이 값이 있을 때만 붙인다.
  final String? label;

  /// 승하차지 번호 — 서버가 준 실제 순서이거나(학부모) 경유 지점을 뺀 순번(매니저)이다. 번호 핀 안에 그린다.
  final int? seq;

  /// 내 승하차지 — 더 크게 · 둘레를 점선으로 강조한다(학부모 앱).
  final bool mine;

  /// 오늘 서지 않는 승하차지(`change=skipped`, C-05) — 흐리게 · 회색 · 번호 취소선으로 그린다(`Ruling
  /// 400`).
  final bool skipped;

  /// 아이콘 모양을 정하는 값의 묶음 — 이 값이 달라지면 어댑터가 마커 아이콘을 다시 만든다(좌표는 제외).
  /// 번호 · 내 승하차지 · 미경유가 바뀌어도 마커 id 는 그대로라, 좌표만 비교하면 옛 아이콘이 남는다.
  String get lookKey => '${kind.name}|$seq|$mine${skipped ? '|skipped' : ''}';
}

/// 지도 위에 그릴 선 하나(예: 확정 노선의 도로 경로). 점은 순서대로 이어진다.
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

  /// 지나온 구간 색 — 운행이 끝난 뒤의 선.
  final bool passed;

  /// 같은 선인지 가르는 값 — 이 값이 달라지면 어댑터가 선을 지우고 다시 그린다.
  String get lookKey =>
      '$dashed|$passed|${Object.hashAll(points.map((p) => (p.lat, p.lng)))}';
}

/// 마커 · 선이 전부 들어오는 최소 사각형 — 카메라를 내용에 맞출 때 쓴다.
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

/// 지도 준비 완료 콜백 — SDK 가 타일을 그릴 준비를 마치면 호출된다.
typedef MapReadyCallback = void Function();

/// 지도 인증 실패 콜백. SDK 예외를 그대로 넘기되(삼키거나 다른 값으로 바꾸지 않는다), 화면이 SDK 예외 타입을
/// 몰라도 되도록 [Object] 로 받는다.
typedef MapAuthFailedCallback = void Function(Object exception);
