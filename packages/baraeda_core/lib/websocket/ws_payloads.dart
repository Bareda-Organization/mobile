/// `API_SPEC §7.1` 이벤트별 payload 모델. 봉투(`WebSocketEnvelope`)의
/// `payload` 는 원문 `Map<String, dynamic>` 으로 남기고, 호출부가 `event` 값에
/// 맞는 `Ws*Payload.fromJson(payload)` 로 다시 파싱한다 — 이벤트마다 필드
/// 모양이 전혀 달라 하나의 클래스로 합칠 수 없다.
///
/// 여기 있는 id 필드(`stop_id` · `run_id` · `next_stop_id`)는 전부 `asIdString` 을 거친다 —
/// payload 안의 식별자 전부가 `Long`/`string` 어느 쪽으로 와도 같다(Ruling 275,
/// `as_id_string.dart` 참고).
library;

import 'package:baraeda_core/id/as_id_string.dart';

/// `position` — 학부모·학생 채널은 [eta] 가 항상 `null`(C-08), 관제 채널만 값이 온다.
class WsPositionPayload {
  /// 값을 그대로 받는다.
  const new({
    required this.lat,
    required this.lng,
    required this.receivedAt,
    required this.currentStopName,
    this.eta,
  });

  /// 봉투 `payload` 원문을 파싱한다 — 키는 `API_SPEC §7.1` 의 snake_case.
  factory fromJson(Map<String, dynamic> json) => WsPositionPayload(
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    receivedAt: DateTime.parse(json['received_at'] as String),
    currentStopName: json['current_stop_name'] as String?,
    // 사양이 eta 의 구체 타입을 명시하지 않는다 — 값이 오면 원문 그대로
    // 문자열로 보존하고, 형태 해석(초 단위 남은 시간인지 절대 시각인지)은
    // 이 함수의 범위 밖이다(관제 채널 소비자가 그때 가서 결정할 문제).
    eta: json['eta']?.toString(),
  );

  /// 위도.
  final double lat;

  /// 경도.
  final double lng;

  /// 서버가 좌표를 받은 시각.
  final DateTime receivedAt;

  /// 직전에 도착한 승하차지 이름 — 아직 없으면 null.
  final String? currentStopName;

  /// 도착 예정 원문 — 관제 채널에서만 값이 온다.
  final String? eta;
}

/// `stop_arrived` — 기사 포인터 전진의 방송. 동승자 처리 명단은 이 이벤트로
/// 바뀌지 않는다(`rider_changed` 가 별도로 온다).
class WsStopArrivedPayload {
  /// 값을 그대로 받는다.
  const new({
    required this.stopId,
    required this.seq,
    required this.name,
    required this.arrivedAt,
    required this.nextStopId,
  });

  /// 봉투 `payload` 원문을 파싱한다 — 키는 `API_SPEC §7.1` 의 snake_case.
  factory fromJson(Map<String, dynamic> json) => WsStopArrivedPayload(
    stopId: asIdString(json['stop_id']),
    seq: json['seq'] as int,
    name: json['name'] as String,
    arrivedAt: DateTime.parse(json['arrived_at'] as String),
    // 마지막 승하차지 도착이면 다음이 없다 — null 허용.
    nextStopId: json['next_stop_id'] == null
        ? null
        : asIdString(json['next_stop_id']),
  );

  /// 승하차지 id.
  final String stopId;

  /// 회차 안의 정차 순번.
  final int seq;

  /// 도착한 승하차지 이름.
  final String name;

  /// 승하차지에 도착한 시각.
  final DateTime arrivedAt;

  /// 다음 승하차지 id — 마지막이면 null.
  final String? nextStopId;
}

/// `run_started` — `run_status` 는 `moving` 고정(§9.3).
///
/// [autoBoardedCount] 는 매니저·관제 채널에만 실린다 — 학생 채널은 인원수를
/// 싣지 않는다(C-08, Ruling 335).
class WsRunStartedPayload {
  /// 값을 그대로 받는다.
  const new({
    required this.runStatus,
    required this.startedAt,
    this.autoBoardedCount,
  });

  /// 봉투 `payload` 원문을 파싱한다 — 키는 `API_SPEC §7.1` 의 snake_case.
  factory fromJson(Map<String, dynamic> json) => WsRunStartedPayload(
    runStatus: json['run_status'] as String,
    startedAt: DateTime.parse(json['started_at'] as String),
    autoBoardedCount: json['auto_boarded_count'] as int?,
  );

  /// 회차 상태 원문.
  final String runStatus;

  /// 운행을 시작한 시각.
  final DateTime startedAt;

  /// 자동 승차 처리 인원 — 학생 채널에는 없다.
  final int? autoBoardedCount;
}

/// `run_ended` — `run_status` 는 `finished` 고정(§9.3).
///
/// [autoAlightedCount] 는 매니저·관제 채널에만 실린다 — 학생 채널은 인원수를
/// 싣지 않는다(C-08, Ruling 335).
class WsRunEndedPayload {
  /// 값을 그대로 받는다.
  const new({
    required this.runStatus,
    required this.finishedAt,
    this.autoAlightedCount,
  });

  /// 봉투 `payload` 원문을 파싱한다 — 키는 `API_SPEC §7.1` 의 snake_case.
  factory fromJson(Map<String, dynamic> json) => WsRunEndedPayload(
    runStatus: json['run_status'] as String,
    finishedAt: DateTime.parse(json['finished_at'] as String),
    autoAlightedCount: json['auto_alighted_count'] as int?,
  );

  /// 회차 상태 원문.
  final String runStatus;

  /// 운행을 마친 시각.
  final DateTime finishedAt;

  /// 자동 하차 처리 인원 — 학생 채널에는 없다.
  final int? autoAlightedCount;
}
