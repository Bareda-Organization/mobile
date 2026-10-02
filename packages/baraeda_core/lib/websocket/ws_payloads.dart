/// `API_SPEC §7.1` 이벤트별 payload 모델. 봉투(`WebSocketEnvelope`)의
/// `payload` 는 원문 `Map<String, dynamic>` 으로 남기고, 호출부가 `event` 값에
/// 맞는 `Ws*Payload.fromJson(payload)` 로 다시 파싱한다 — 이벤트마다 필드
/// 모양이 전혀 달라 하나의 클래스로 합칠 수 없다.
///
/// 여기 있는 id 필드(`stop_id` · `rider_id` · `student_id` · `emergency_id` ·
/// `run_id` · `next_stop_id`)는 전부 `asIdString` 을 거친다 — `run_id` 하나만
/// 흔들리는 게 아니라 payload 안의 식별자 전부가 같은 사정이다(Ruling 275,
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
  factory fromJson(Map<String, dynamic> json) =>
      WsPositionPayload(
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
  factory fromJson(Map<String, dynamic> json) =>
      WsStopArrivedPayload(
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

/// `rider_changed` — 5초 이내 반영. `counts`·`status` 의 정확한 하위 구조는
/// 사양이 값 사전을 별도로 두지 않아 원문 그대로 넘긴다.
class WsRiderChangedPayload {
  /// 값을 그대로 받는다.
  const new({
    required this.riderId,
    required this.studentId,
    required this.studentName,
    required this.status,
    required this.stopId,
    required this.changedAt,
    required this.counts,
    required this.stopSkipped,
  });

  /// 봉투 `payload` 원문을 파싱한다 — 키는 `API_SPEC §7.1` 의 snake_case.
  factory fromJson(Map<String, dynamic> json) =>
      WsRiderChangedPayload(
        riderId: asIdString(json['rider_id']),
        studentId: asIdString(json['student_id']),
        studentName: json['student_name'] as String,
        // `RunRider.status` — waiting·boarded·alighted·absent·no_show
        // (§9.4). enum 화는 이 패키지가 아니라 소비 화면 쪽 관심사다.
        status: json['status'] as String,
        stopId: asIdString(json['stop_id']),
        changedAt: DateTime.parse(json['changed_at'] as String),
        counts: (json['counts'] as Map).cast<String, dynamic>(),
        stopSkipped: json['stop_skipped'] as bool,
      );

  /// 동승자 id.
  final String riderId;

  /// 학생 id.
  final String studentId;

  /// 학생 이름.
  final String studentName;

  /// `RunRider.status` 원문(waiting·boarded·alighted·absent·no_show).
  final String status;

  /// 승하차지 id.
  final String stopId;

  /// 상태가 바뀐 시각.
  final DateTime changedAt;

  /// 인원 집계 원문.
  final Map<String, dynamic> counts;

  /// 이 승하차지에 정차하지 않는지.
  final bool stopSkipped;
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
  factory fromJson(Map<String, dynamic> json) =>
      WsRunStartedPayload(
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
  factory fromJson(Map<String, dynamic> json) =>
      WsRunEndedPayload(
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

/// [WsEmergencyRaisedPayload.raisedBy] 하위 객체.
class WsEmergencyRaisedBy {
  /// 값을 그대로 받는다.
  const new({
    required this.name,
    required this.role,
    required this.phone,
  });

  /// 봉투 `payload` 원문을 파싱한다 — 키는 `API_SPEC §7.1` 의 snake_case.
  factory fromJson(Map<String, dynamic> json) =>
      WsEmergencyRaisedBy(
        name: json['name'] as String,
        role: json['role'] as String,
        phone: json['phone'] as String,
      );

  /// 신고자 이름.
  final String name;

  /// 신고자 역할 원문.
  final String role;

  /// 신고자 연락처.
  final String phone;
}

/// [WsEmergencyRaisedPayload.position] 하위 객체 — 발신 시점 좌표.
class WsEmergencyPosition {
  /// 값을 그대로 받는다.
  const new({required this.lat, required this.lng});

  /// 봉투 `payload` 원문을 파싱한다 — 키는 `API_SPEC §7.1` 의 snake_case.
  factory fromJson(Map<String, dynamic> json) =>
      WsEmergencyPosition(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
      );

  /// 위도.
  final double lat;

  /// 경도.
  final double lng;
}

/// `emergency_raised` — 관계자·메인 관리자 채널 전용(C-17).
class WsEmergencyRaisedPayload {
  /// 값을 그대로 받는다.
  const new({
    required this.emergencyId,
    required this.type,
    required this.busNo,
    required this.raisedBy,
    required this.position,
    required this.riderCount,
    required this.raisedAt,
  });

  /// 봉투 `payload` 원문을 파싱한다 — 키는 `API_SPEC §7.1` 의 snake_case.
  factory fromJson(Map<String, dynamic> json) =>
      WsEmergencyRaisedPayload(
        emergencyId: asIdString(json['emergency_id']),
        type: json['type'] as String,
        busNo: json['bus_no'] as String,
        raisedBy: WsEmergencyRaisedBy.fromJson(
          (json['raised_by'] as Map).cast<String, dynamic>(),
        ),
        position: WsEmergencyPosition.fromJson(
          (json['position'] as Map).cast<String, dynamic>(),
        ),
        // 발신 시점 회차에 배정된 라이더 전원 수 — 승하차 상태 무관.
        riderCount: json['rider_count'] as int,
        raisedAt: DateTime.parse(json['raised_at'] as String),
      );

  /// 비상 신고 id.
  final String emergencyId;

  /// 비상 유형 원문.
  final String type;

  /// 호차 이름.
  final String busNo;

  /// 신고자.
  final WsEmergencyRaisedBy raisedBy;

  /// 신고 시점 좌표.
  final WsEmergencyPosition position;

  /// 신고 시점 회차에 배정된 동승자 전원 수.
  final int riderCount;

  /// 신고 시각.
  final DateTime raisedAt;
}

/// `emergency_acked` — 매니저 채널 전용. 발신자 앱에 "학원이 확인했습니다" 표시(A-16).
class WsEmergencyAckedPayload {
  /// 값을 그대로 받는다.
  const new({
    required this.emergencyId,
    required this.ackedByName,
    required this.ackedAt,
  });

  /// 봉투 `payload` 원문을 파싱한다 — 키는 `API_SPEC §7.1` 의 snake_case.
  factory fromJson(Map<String, dynamic> json) =>
      WsEmergencyAckedPayload(
        emergencyId: asIdString(json['emergency_id']),
        ackedByName: json['acked_by_name'] as String,
        ackedAt: DateTime.parse(json['acked_at'] as String),
      );

  /// 비상 신고 id.
  final String emergencyId;

  /// 확인한 관계자 이름.
  final String ackedByName;

  /// 확인한 시각.
  final DateTime ackedAt;
}

/// `approval_requested` — 관계자 채널 전용(REQ-05).
class WsApprovalRequestedPayload {
  /// 값을 그대로 받는다.
  const new({
    required this.approvalId,
    required this.studentName,
    required this.runId,
    required this.stopName,
    required this.deadlineAt,
  });

  /// 봉투 `payload` 원문을 파싱한다 — 키는 `API_SPEC §7.1` 의 snake_case.
  factory fromJson(Map<String, dynamic> json) =>
      WsApprovalRequestedPayload(
        approvalId: asIdString(json['approval_id']),
        studentName: json['student_name'] as String,
        runId: asIdString(json['run_id']),
        stopName: json['stop_name'] as String,
        deadlineAt: DateTime.parse(json['deadline_at'] as String),
      );

  /// 승인 요청 id.
  final String approvalId;

  /// 학생 이름.
  final String studentName;

  /// 회차 id.
  final String runId;

  /// 승하차지 이름.
  final String stopName;

  /// 승인 마감 시각.
  final DateTime deadlineAt;
}
