import 'package:parent_app/core/common/json_id.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';

/// 그 회차의 마지막 지연 알림(§3.11 `delay`, `Ruling 821`) — 지연 안내 띠의 원천.
///
/// ETA 가 아니라 학원이 보낸 지연 알림(NTF-07)이다. 없거나 회차가 끝났거나 미등원이면 서버가 `null`.
class BusDelay {
  const new({required this.minutes, required this.sentAt, this.reason});

  factory fromJson(Map<String, dynamic> json) => BusDelay(
    minutes: json['minutes'] as int,
    reason: json['reason'] as String?,
    sentAt: DateTime.parse(json['sent_at'] as String),
  );

  final int minutes;
  final String? reason;
  final DateTime sentAt;
}

/// `GET /students/{id}/bus-position` 응답 — API_SPEC §3.11.
///
/// `lat`·`lng`·`received_at`·`last_seen_at`·`current_stop_name` 전부
/// 선택값이다 — `run_status` 가 `moving` 이 아니거나 당일 결석
/// (`RiderStatus.absent`, `student_run.dart` 참고 — 이 응답 자체에는
/// 결석 여부가 없어 `runsForStudentProvider` 와 `run_id` 로 대조해야
/// 한다)이면 좌표가 통째로 부재한다. **ETA·좌석별 탑승 인원은 의도적으로
/// 부재**(§7.1 — 학부모·학생 채널은 ETA 를 절대 받지 않는다, C-08) —
/// 이 모델에 추가하지 않는다.
class BusPosition {
  const new({
    required this.runId,
    required this.busNo,
    required this.runStatus,
    this.lat,
    this.lng,
    this.receivedAt,
    this.lastSeenAt,
    this.currentStopName,
    this.currentStopArrivedAt,
    this.startedAt,
    this.finishedAt,
    this.delay,
  });

  factory fromJson(Map<String, dynamic> json) => BusPosition(
    runId: asIdString(json['run_id']),
    busNo: json['bus_no'] as String,
    runStatus: RunStatus.fromWireValue(json['run_status'] as String),
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
    receivedAt: json['received_at'] == null
        ? null
        : DateTime.parse(json['received_at'] as String),
    lastSeenAt: json['last_seen_at'] == null
        ? null
        : DateTime.parse(json['last_seen_at'] as String),
    currentStopName: json['current_stop_name'] as String?,
    currentStopArrivedAt: _optionalTime(json['current_stop_arrived_at']),
    startedAt: _optionalTime(json['started_at']),
    finishedAt: _optionalTime(json['finished_at']),
    delay: json['delay'] == null
        ? null
        : BusDelay.fromJson(json['delay'] as Map<String, dynamic>),
  );

  static DateTime? _optionalTime(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  final String runId;
  final String busNo;
  final RunStatus runStatus;
  final double? lat;
  final double? lng;
  final DateTime? receivedAt;

  /// 신호 유실 시 마지막 확인 시각 — 유실 판정(수신 후 2분, Ruling 208)
  /// 자체는 서버가 하고, 클라이언트는 이 값으로 "N분 전" 문구만 계산한다
  /// (`live_map_screen.dart` 참고).
  final DateTime? lastSeenAt;
  final String? currentStopName;

  /// "마지막으로 지난 곳 · 12:09" 의 시각(`Ruling 821`). 이름과 같은 조건에서만 채워진다.
  final DateTime? currentStopArrivedAt;

  /// 실제 운행 시작 · 종료 시각 — 지나기 전이면 `null`. WebSocket 이벤트를 놓치고 들어와도 그린다.
  final DateTime? startedAt;
  final DateTime? finishedAt;

  /// 마지막 지연 알림 — 지연 띠. `null` 이면 띠를 그리지 않는다.
  final BusDelay? delay;
}
