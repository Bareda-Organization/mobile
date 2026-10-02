/// 외부 내비에 넘길 지점 하나 — 위도·경도·이름.
class NavigationPoint {
  const new({
    required this.lat,
    required this.lng,
    required this.name,
  });

  factory fromJson(Map<String, dynamic> json) =>
      NavigationPoint(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        name: json['name'] as String,
      );

  final double lat;
  final double lng;
  final String name;
}

/// `GET /runs/{runId}/navigation` 응답(API_SPEC §4.16, RUN-08) — 서버가 순서를 정하고 공급자 상한만큼 자른 좌표열.
/// 딥링크는 서버가 만들지 않는다 — 앱이 공식 SDK(`kakaoNaviRequest`)로 카카오내비를 연다.
class NavigationRoute {
  const new({
    required this.provider,
    required this.waypoints,
    required this.destination,
    required this.truncated,
    required this.totalRemainingStops,
    this.origin,
    this.truncatedReason,
  });

  factory fromJson(Map<String, dynamic> json) {
    final origin = json['origin'] as Map<String, dynamic>?;
    return NavigationRoute(
      provider: json['provider'] as String,
      origin: origin == null ? null : NavigationPoint.fromJson(origin),
      waypoints: [
        for (final point in json['waypoints'] as List<dynamic>)
          NavigationPoint.fromJson(point as Map<String, dynamic>),
      ],
      destination: NavigationPoint.fromJson(
        json['destination'] as Map<String, dynamic>,
      ),
      truncated: json['truncated'] as bool,
      truncatedReason: json['truncated_reason'] as String?,
      totalRemainingStops: json['total_remaining_stops'] as int,
    );
  }

  /// 서버가 정한 활성 내비 공급자(`kakao`). 앱은 이 값으로 띄울 내비를 고른다.
  final String provider;

  /// 운행 중(`moving`)이면 `null` — 내비가 현재 위치에서 출발한다.
  final NavigationPoint? origin;

  /// 경유지 — 순서가 곧 주행 순서다.
  final List<NavigationPoint> waypoints;
  final NavigationPoint destination;

  /// 상한 때문에 남은 승하차지를 다 못 넘겼는지.
  final bool truncated;

  /// [truncated] 일 때 화면에 보일 안내 문구.
  final String? truncatedReason;

  /// 자르기 전 남은 승하차지 수.
  final int totalRemainingStops;
}
