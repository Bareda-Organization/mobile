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
/// (P-08). **화면은 이 목록(`stops`)을 직접 그리지 않고 [RouteDetail.
/// visibleStops] 를 그린다** — 서버 응답이 계약대로 좁혀지지 않은 채
/// 와도(다른 소비자·서버 변경) 화면이 §3.10 범위 밖을 그리지 않도록
/// 클라이언트에서 같은 창을 다시 계산한다(근거는 `RouteDetail.
/// visibleStops` 문서).
class RouteStop {
  const RouteStop({
    required this.stopId,
    required this.seq,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.change,
  });

  factory RouteStop.fromJson(Map<String, dynamic> json) => RouteStop(
    stopId: asIdString(json['stop_id']),
    seq: json['seq'] as int,
    name: json['name'] as String,
    address: json['address'] as String,
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    change: RouteStopChange.fromWireValue(json['change'] as String?),
  );

  final String stopId;
  final int seq;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final RouteStopChange? change;
}

/// 기사 이름만 — 기사는 연락처가 부재하다(학부모 → 기사 직접 연락은
/// 스코프 제외, API_SPEC §3.10 `escort.phone` 설명 참고).
class RouteDriver {
  const RouteDriver({required this.name});

  factory RouteDriver.fromJson(Map<String, dynamic> json) =>
      RouteDriver(name: json['name'] as String);

  final String name;
}

/// 동승자 — 연락 버튼은 이 사람만 갖는다.
class RouteEscort {
  const RouteEscort({required this.name, required this.phone});

  factory RouteEscort.fromJson(Map<String, dynamic> json) => RouteEscort(
    name: json['name'] as String,
    phone: json['phone'] as String,
  );

  final String name;
  final String phone;
}

/// `GET /students/{id}/route` 응답 (API_SPEC §3.10).
///
/// **승하차지별 탑승 인원·ETA 필드는 의도적으로 부재** (C-08) — 이 모델에
/// 추가하지 않는다. 서버가 안 주는 값을 클라이언트가 계산해 채우면 규칙을
/// 우회하는 셈이다(`core/runs/domain/student_run.dart` 와 같은 원칙).
class RouteDetail {
  const RouteDetail({
    required this.runId,
    required this.busNo,
    required this.departTime,
    required this.confirmed,
    required this.driver,
    required this.escort,
    required this.myStopId,
    required this.stops,
  });

  factory RouteDetail.fromJson(Map<String, dynamic> json) => RouteDetail(
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
  final List<RouteStop> stops;

  /// 화면이 실제로 그릴 목록 — **서버가 이미 좁혀 보내는 것과 별개로
  /// 클라이언트에서 다시 창을 계산한다.**
  ///
  /// **판단 근거 — 방어적 이중화다.** 서버 쪽 알고리즘은
  /// `StudentRouteQueryService.window()` 의
  /// `entries.subList(max(0, myIndex - 2), myIndex + 1)` 이다(내 승하차지
  /// 이전 2개 + 내 승하차지, 그 뒤는 없음). 이 화면은 원래 그 계약을
  /// 신뢰하고 [stops] 를 그대로 그렸는데, 그 신뢰가 **다른 집 아이의
  /// 승하차지 좌표 노출**로 이어질 수 있다 — 서버 쪽 회귀나 이 모델을
  /// 재사용하는 다른 소비자가 창을 안 좁힌 응답을 주면 방어 수단이 없었다.
  /// 그래서 서버와 **같은 알고리즘**을 여기서도 돌려, 무엇이 오든 화면은
  /// 항상 §3.10 범위 안쪽만 그린다.
  ///
  /// [myStopId] 를 [stops] 에서 못 찾으면 빈 목록을 돌려준다 — 서버도
  /// 같은 경우 빈 창을 돌려준다(`window()` 의 `myIndex < 0` 분기).
  List<RouteStop> get visibleStops {
    final myIndex = stops.indexWhere((stop) => stop.stopId == myStopId);
    if (myIndex < 0) return const [];
    final start = myIndex - 2 < 0 ? 0 : myIndex - 2;
    return stops.sublist(start, myIndex + 1);
  }
}
