import 'package:parent_app/core/common/run_direction.dart';

/// `GET /students/{id}/runs` 응답 항목 (API_SPEC §3.5).
///
/// **ETA·탑승 인원 필드는 의도적으로 부재** (C-08) — 이 모델에 추가하지
/// 않는다. 서버가 안 주는 값을 클라이언트가 계산해 채우면 규칙을 우회하는
/// 셈이다.
enum RunStatus {
  idle,
  confirmed,
  moving,
  finished;

  static RunStatus fromWireValue(String value) => switch (value) {
    'idle' => RunStatus.idle,
    'confirmed' => RunStatus.confirmed,
    'moving' => RunStatus.moving,
    'finished' => RunStatus.finished,
    _ => throw ArgumentError('알 수 없는 run_status: $value'),
  };
}

enum RiderStatus {
  waiting,
  boarded,
  alighted,
  absent,
  noShow;

  static RiderStatus fromWireValue(String value) => switch (value) {
    'waiting' => RiderStatus.waiting,
    'boarded' => RiderStatus.boarded,
    'alighted' => RiderStatus.alighted,
    'absent' => RiderStatus.absent,
    'no_show' => RiderStatus.noShow,
    _ => throw ArgumentError('알 수 없는 rider_status: $value'),
  };
}

/// 본인 승하차지 — `stop_id` · `name` · `address`.
class RunStop {
  const RunStop({required this.stopId, required this.name, this.address});

  factory RunStop.fromJson(Map<String, dynamic> json) => RunStop(
    stopId: json['stop_id'] as String,
    name: json['name'] as String,
    address: json['address'] as String?,
  );

  final String stopId;
  final String name;
  final String? address;
}

class StudentRun {
  const StudentRun({
    required this.runId,
    required this.direction,
    required this.busNo,
    required this.departTime,
    required this.runStatus,
    required this.confirmed,
    required this.riding,
    required this.riderStatus,
    required this.stop,
    required this.changeQuotaLeft,
  });

  factory StudentRun.fromJson(Map<String, dynamic> json) => StudentRun(
    runId: json['run_id'] as String,
    direction: RunDirection.fromWireValue(json['direction'] as String),
    busNo: json['bus_no'] as String,
    departTime: DateTime.parse(json['depart_time'] as String),
    runStatus: RunStatus.fromWireValue(json['run_status'] as String),
    confirmed: json['confirmed'] as bool,
    riding: json['riding'] as bool,
    riderStatus: RiderStatus.fromWireValue(json['rider_status'] as String),
    stop: RunStop.fromJson(json['stop'] as Map<String, dynamic>),
    changeQuotaLeft: json['change_quota_left'] as int,
  );

  final String runId;
  final RunDirection direction;
  final String busNo;
  final DateTime departTime;
  final RunStatus runStatus;

  /// 확정 노선 산출 여부 — 출발 30분 전 배치 결과.
  final bool confirmed;

  /// 탑승 의사(ATT-01).
  final bool riding;
  final RiderStatus riderStatus;
  final RunStop stop;

  /// 이 회차의 ② 구간 잔여 변경 횟수 — 회차당 1회, 다른 회차와 독립.
  final int changeQuotaLeft;
}
