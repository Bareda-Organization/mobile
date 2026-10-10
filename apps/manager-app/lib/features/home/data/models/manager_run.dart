import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';

/// `GET /manager/runs` 항목 (API_SPEC §4.1, RUN-01 · M-02·M-07).
class ManagerRun {
  const new({
    required this.runId,
    required this.busNo,
    required this.direction,
    required this.departTime,
    required this.origin,
    required this.destination,
    required this.runStatus,
    required this.confirmed,
    required this.startWindowFrom,
    required this.startWindowTo,
    required this.addedCount,
    required this.removedCount,
    required this.ackRequired,
    this.estDurationMin,
    this.roleInRun,
    this.confirmAt,
    this.plateNo,
    this.riderCount,
    this.absentCount,
    this.stopCount,
  });

  factory fromJson(Map<String, dynamic> json) {
    final startWindow = json['start_window'] as Map<String, dynamic>;
    return ManagerRun(
      runId: json['run_id'] as String,
      busNo: json['bus_no'] as String,
      direction:
          RunDirection.fromWireValueOrNull(json['direction'] as String?) ??
          RunDirection.toAcademy,
      departTime: DateTime.parse(json['depart_time'] as String),
      origin: json['origin'] as String,
      destination: json['destination'] as String,
      estDurationMin: json['est_duration_min'] as int?,
      runStatus:
          RunStatus.fromWireValueOrNull(json['run_status'] as String?) ??
          RunStatus.idle,
      confirmed: json['confirmed'] as bool,
      confirmAt: json['confirm_at'] == null
          ? null
          : DateTime.parse(json['confirm_at'] as String),
      startWindowFrom: DateTime.parse(startWindow['from'] as String),
      startWindowTo: DateTime.parse(startWindow['to'] as String),
      addedCount: json['added_count'] as int,
      removedCount: json['removed_count'] as int,
      ackRequired: json['ack_required'] as bool,
      roleInRun: switch (json['role_in_run']) {
        final String wire => UserRole.fromWireValueOrNull(wire),
        _ => null,
      },
      // R48 Ruling 822 — 서버가 아직 안 주거나 확정 전이면 `null`. 값이 없으면 화면은 그 줄을 숨긴다.
      plateNo: json['plate_no'] as String?,
      riderCount: json['rider_count'] as int?,
      absentCount: json['absent_count'] as int?,
      stopCount: json['stop_count'] as int?,
    );
  }

  /// 기기에 남기는 회차 요약(R52 H2) — `fromJson` 이 그대로 읽는 §4.1 항목 모양이다.
  /// 학생 · 보호자 정보는 이 항목에 없다.
  Map<String, dynamic> toJson() => {
    'run_id': runId,
    'bus_no': busNo,
    'direction': direction.wireValue,
    'depart_time': departTime.toIso8601String(),
    'origin': origin,
    'destination': destination,
    'est_duration_min': estDurationMin,
    'run_status': runStatus.wireValue,
    'confirmed': confirmed,
    'confirm_at': confirmAt?.toIso8601String(),
    'start_window': {
      'from': startWindowFrom.toIso8601String(),
      'to': startWindowTo.toIso8601String(),
    },
    'added_count': addedCount,
    'removed_count': removedCount,
    'ack_required': ackRequired,
    'role_in_run': roleInRun?.wireValue,
    'plate_no': plateNo,
    'rider_count': riderCount,
    'absent_count': absentCount,
    'stop_count': stopCount,
  };

  final String runId;

  /// 호차.
  final String busNo;
  final RunDirection direction;
  final DateTime departTime;
  final String origin;
  final String destination;

  /// 스케줄이 값을 안 적었으면 `null`(§4.1) — 화면은 소요 시간 줄을 그리지 않는다.
  final int? estDurationMin;
  final RunStatus runStatus;

  /// `false` 면 명단 진입 불가(§4.2 `409 RUN_NOT_CONFIRMED`).
  final bool confirmed;

  /// 확정 예정 시각 = 출발 30분 전. 미확정 회차만 값이 있다.
  final DateTime? confirmAt;
  final DateTime startWindowFrom;
  final DateTime startWindowTo;

  /// 변경 배지.
  final int addedCount;
  final int removedCount;

  /// 노선 변경 확인 응답 미완료 여부(RUN-07). §4.11 `ack-changes` 호출이
  /// 성공하면 `false` 로 바뀐다 — StopRoster(`roster_screen.dart`)가 이
  /// 값을 배너 노출 근거로 쓴다(정정: 과거 주석은 §4.11 을 범위 밖으로
  /// 잘못 적었었다).
  final bool ackRequired;

  /// `null` 이면 서버가 이 앱이 모르는 역할을 줬다는 뜻 — 화면 구성은
  /// `roleCapabilitiesProvider`(로그인 시점 값)를 따로 쓰므로 이 필드
  /// 자체가 화면 분기에 쓰이지는 않는다.
  final UserRole? roleInRun;

  /// 차량번호 — 내 정보의 "담당 차량"(`Ruling 822`). 서버가 아직 안 주면 `null`.
  final String? plateNo;

  /// 탑승 예정 인원(`absent` 제외) · 미등원 인원 · 승하차지 수(경유 지점·도착지 제외, `Ruling 822`).
  /// 확정 전(`confirmed=false`)이면 셋 다 `null` — 화면은 숫자 줄 전체를 숨긴다.
  final int? riderCount;
  final int? absentCount;
  final int? stopCount;
}
