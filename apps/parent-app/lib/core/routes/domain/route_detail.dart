import 'package:parent_app/core/common/json_id.dart';

/// `stops[].change` — `added` · `skipped` 뿐이다. 승하차지에는 `removed` 가
/// 부재하다: 탑승자 삭제는 승하차지가 아니라 명단(roster)에 반영된다
/// (FEATURE_SPEC §3.5, API_SPEC §3.10).
enum RouteStopChange {
  added,
  skipped;

  static RouteStopChange? fromWireValue(String? value) => switch (value) {
    null => null,
    'added' => RouteStopChange.added,
    'skipped' => RouteStopChange.skipped,
    _ => throw ArgumentError('알 수 없는 stops[].change: $value'),
  };
}

/// 노선의 승하차지 1개.
///
/// 서버가 이미 "승차지 이전 2개 · 승차지 · 하차지" 로 창을 좁혀 보낸다
/// (P-08, `StudentRouteQueryService.window()`) — 화면은 이 목록(`stops`)을
/// 그대로 그린다(`RouteDetailScreen` 참고, Ruling 288/목표 2).
///
/// **`address`·`lat`·`lng` 는 `null` 일 수 있다** — 등원(TO_ACADEMY)의
/// 하차지·하원(FROM_ACADEMY)의 승차지로 서버가 합성해 붙이는 학원 항목은
/// `Academy` 엔티티 값을 그대로 옮기는데, `academy.address`·`lat`·`lng` 는
/// DB 상 nullable 이다(`V1__init_schema.sql`). API_SPEC §1.13 도 경유
/// 지점류 항목의 이 필드들이 `null` 일 수 있다고 이미 규정한다.
class RouteStop {
  const new({
    required this.stopId,
    required this.seq,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.change,
  });

  factory fromJson(Map<String, dynamic> json) => RouteStop(
    stopId: asIdString(json['stop_id']),
    seq: json['seq'] as int,
    name: json['name'] as String,
    address: json['address'] as String?,
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
    change: RouteStopChange.fromWireValue(json['change'] as String?),
  );

  final String stopId;
  final int seq;
  final String name;
  final String? address;
  final double? lat;
  final double? lng;
  final RouteStopChange? change;
}

/// 기사 이름만 — 기사는 연락처가 부재하다(학부모 → 기사 직접 연락은
/// 스코프 제외, API_SPEC §3.10 `escort.phone` 설명 참고). 배치 전 회차는
/// `null`(§3.10 `◐`).
class RouteDriver {
  const new({required this.name});

  factory fromJson(Map<String, dynamic> json) =>
      RouteDriver(name: json['name'] as String?);

  final String? name;
}

/// 동승자 — 연락 버튼은 이 사람만 갖는다. 배치 전 회차는 이름·연락처가
/// `null`(§3.10 `◐`).
class RouteEscort {
  const new({required this.name, required this.phone});

  factory fromJson(Map<String, dynamic> json) => RouteEscort(
    name: json['name'] as String?,
    phone: json['phone'] as String?,
  );

  final String? name;
  final String? phone;
}

/// `GET /students/{id}/route` 응답 (API_SPEC §3.10).
///
/// **승하차지별 탑승 인원·ETA 필드는 의도적으로 부재** (C-08) — 이 모델에
/// 추가하지 않는다. 서버가 안 주는 값을 클라이언트가 계산해 채우면 규칙을
/// 우회하는 셈이다(`core/runs/domain/student_run.dart` 와 같은 원칙).
class RouteDetail {
  const new({
    required this.runId,
    required this.busNo,
    required this.departTime,
    required this.confirmed,
    required this.driver,
    required this.escort,
    required this.myStopId,
    required this.stops,
  });

  factory fromJson(Map<String, dynamic> json) => RouteDetail(
    runId: asIdString(json['run_id']),
    busNo: json['bus_no'] as String,
    departTime: DateTime.parse(json['depart_time'] as String),
    confirmed: json['confirmed'] as bool,
    driver: RouteDriver.fromJson(json['driver'] as Map<String, dynamic>),
    escort: RouteEscort.fromJson(json['escort'] as Map<String, dynamic>),
    myStopId: asIdString(json['my_stop_id']),
    stops: (json['stops'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(RouteStop.fromJson)
        .toList(),
  );

  final String runId;
  final String busNo;
  final DateTime departTime;

  /// `false` = 아직 배치 전 — 고정(기본) 노선을 그대로 보여주고 "확정 전"
  /// 배지만 얹는다. 이 상태는 에러가 아니다(API_SPEC §3.10 에러 표 마지막
  /// 줄 — "확정 전은 에러 부재").
  final bool confirmed;
  final RouteDriver driver;
  final RouteEscort escort;

  /// 본인 승하차지 — [stops] 중 이 `stopId` 와 일치하는 항목을 강조해 그린다.
  final String myStopId;

  /// 화면이 그릴 목록 그 자체 — 서버 응답을 그대로 쓴다.
  ///
  /// **판단 근거(목표 2, `visibleStops` 삭제)** — 이전에는 클라이언트가
  /// 서버와 같은 windowing 알고리즘을 여기서 한 번 더 돌려 "서버 계약이
  /// 깨져도 방어" 하려 했다. 그런데 Ruling 288 로 서버가 학원 항목을
  /// windowed 범위 **밖**에 별도로 붙이게 되면서(등원은 뒤·하원은 앞),
  /// 그 옛 알고리즘은 매번 학원 항목을 창 밖으로 오판해 잘라냈다 —
  /// "방어" 가 오히려 정상 응답을 훼손했다. 서버 알고리즘을 클라이언트가
  /// 따로 유지하는 이중화는 한쪽이 바뀌면 반드시 어긋난다. 이 화면은
  /// `GET /students/{id}/route` 전용이라(다른 소비자가 재사용하지
  /// 않는다) 서버를 신뢰하는 것이 유일한 소비자에게는 맞는 계약이다.
  final List<RouteStop> stops;
}
