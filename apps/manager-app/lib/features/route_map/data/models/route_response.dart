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
  });

  factory RouteStop.fromJson(Map<String, dynamic> json) {
    return RouteStop(
      stopId: json['stop_id'] as String,
      seq: json['seq'] as int,
      name: json['name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      address: json['address'] as String?,
      change: RouteStopChange.fromWireValueOrNull(
        json['change'] as String?,
      ),
      studentCount: json['student_count'] as int?,
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
  });

  factory RouteResponse.fromJson(Map<String, dynamic> json) {
    final stopsJson = json['stops'] as List<dynamic>? ?? [];
    final currentStopJson = json['current_stop'] as Map<String, dynamic>?;
    final nextStopJson = json['next_stop'] as Map<String, dynamic>?;
    return RouteResponse(
      stops: stopsJson
          .cast<Map<String, dynamic>>()
          .map(RouteStop.fromJson)
          .toList(),
      currentStop: currentStopJson == null
          ? null
          : RouteStop.fromJson(currentStopJson),
      nextStop: nextStopJson == null ? null : RouteStop.fromJson(nextStopJson),
      skippedNotice: json['skipped_notice'] as String?,
    );
  }

  final List<RouteStop> stops;
  final RouteStop? currentStop;
  final RouteStop? nextStop;
  final String? skippedNotice;
}
