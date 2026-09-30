import 'package:baraeda_core/baraeda_core.dart';

/// `stops[].change` — API_SPEC §4.3. `roster_response.dart` 의 `StopChange`
/// 와 같은 wire 값(added·skipped)이지만, 응답 스키마가 다른 엔드포인트라
/// 타입을 공유하지 않는다(그 파일의 관례를 그대로 따른다).
enum RouteStopChange {
  added('added'),
  skipped('skipped');

  const RouteStopChange(this.wireValue);

  final String wireValue;

  static RouteStopChange? fromWireValueOrNull(String? value) {
    for (final change in RouteStopChange.values) {
      if (change.wireValue == value) return change;
    }
    return null;
  }
}

/// `stops[]` 항목 및 `current_stop`·`next_stop` 공용 모양 — §4.3.
///
/// `current_stop`·`next_stop` 이 `stops[]` 의 부분집합만 채워 보낼 수 있어
/// (표에는 `next_stop.lat`·`next_stop.lng` 만 필수로 명시) `address` ·
/// `change` · `studentCount` 는 널 허용으로 둔다. `stopId` · `seq` · `name` ·
/// `lat` · `lng` 는 세 자리(목록·현재·다음) 모두에서 항상 온다고 가정한다 —
/// 정본에 이 셋이 서로 다른 하위 집합을 보낸다는 근거는 없다(확신 없는
/// 지점, 보고서 2항).
class RouteStop {
  const RouteStop({
    required this.stopId,
    required this.seq,
    required this.name,
    required this.lat,
    required this.lng,
    this.address,
    this.change,
    this.studentCount,
    this.isWaypoint = false,
  });

  factory RouteStop.fromJson(Map<String, dynamic> json) {
    return RouteStop(
      // `Ruling 275` — 서버가 stop_id 를 int 로 내려도 흡수한다(직접 캐스트 금지).
      stopId: asIdString(json['stop_id']),
      seq: json['seq'] as int,
      name: json['name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      address: json['address'] as String?,
      change: RouteStopChange.fromWireValueOrNull(
        json['change'] as String?,
      ),
      studentCount: json['student_count'] as int?,
      isWaypoint: json['is_waypoint'] as bool? ?? false,
    );
  }

  final String stopId;
  final int seq;
  final String name;
  final double lat;
  final double lng;
  final String? address;
  final RouteStopChange? change;
  final int? studentCount;

  /// 강제 경유 지점(§5.15) 항목이면 `true`(`Ruling 400`). 승하차지와 다른 모양의 번호 없는 마커로
  /// 그리고 승하차지 번호에서 뺀다 — 옛 응답에는 없어 없으면 승하차지로 읽는다.
  final bool isWaypoint;
}

/// `GET /runs/{runId}/route` 응답 전체 — §4.3.
///
/// 미경유(`skipped`)는 표시만 하고 재최적화·ETA 재계산·경로 안내는 하지
/// 않는다(C-05, 정본 문구 그대로) — 이 모델도 좌표를 그대로 옮길 뿐 경로를
/// 계산하지 않는다.
class RouteResponse {
  const RouteResponse({
    required this.stops,
    this.currentStop,
    this.nextStop,
    this.skippedNotice,
    this.roadPath = const [],
    this.fallbackUsed = false,
  });

  factory RouteResponse.fromJson(Map<String, dynamic> json) {
    final stopsJson = json['stops'] as List<dynamic>? ?? [];
    final currentStopJson = json['current_stop'] as Map<String, dynamic>?;
    final nextStopJson = json['next_stop'] as Map<String, dynamic>?;
    return RouteResponse(
      // 배포 뒤 제거된 경유 지점은 이름·좌표가 null 인 채 stops[] 에 남는다(§1.13) — 그릴 수 없어 뺀다.
      stops: stopsJson
          .cast<Map<String, dynamic>>()
          .where(
            (json) =>
                json['name'] != null &&
                json['lat'] != null &&
                json['lng'] != null,
          )
          .map(RouteStop.fromJson)
          .toList(),
      currentStop: currentStopJson == null
          ? null
          : RouteStop.fromJson(currentStopJson),
      nextStop: nextStopJson == null ? null : RouteStop.fromJson(nextStopJson),
      skippedNotice: json['skipped_notice'] as String?,
      // R32-M1 — 서버가 이 두 필드를 얹기 전 응답에는 없다. 없으면 빈 선·근사 아님으로 읽는다.
      roadPath: [
        for (final point in json['road_path'] as List<dynamic>? ?? [])
          (
            lat: ((point as Map<String, dynamic>)['lat'] as num).toDouble(),
            lng: (point['lng'] as num).toDouble(),
          ),
      ],
      fallbackUsed: json['fallback_used'] as bool? ?? false,
    );
  }

  final List<RouteStop> stops;
  final RouteStop? currentStop;
  final RouteStop? nextStop;
  final String? skippedNotice;

  /// 확정 노선의 도로 좌표열(순서 있음, `road_path[{lat,lng}]`) — 없거나 비어 있을 수 있다.
  /// 2점 미만이면 선으로 그릴 수 없으므로 화면은 승하차지 핀만 보인다.
  final List<({double lat, double lng})> roadPath;

  /// `true` 면 [roadPath] 가 실제 도로가 아니라 직선거리 근사다(`Ruling 309`) — 화면이 표시한다.
  final bool fallbackUsed;
}
