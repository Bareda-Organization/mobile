import 'package:parent_app/core/common/json_id.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';

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
  );

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
}
