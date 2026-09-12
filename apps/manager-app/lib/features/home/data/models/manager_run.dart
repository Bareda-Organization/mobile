import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';

/// `GET /manager/runs` 항목 (API_SPEC §4.1, RUN-01 · M-02·M-07).
class ManagerRun {
  const ManagerRun({
    required this.runId,
    required this.busNo,
    required this.direction,
    required this.departTime,
    required this.origin,
    required this.destination,
    required this.estDurationMin,
    required this.runStatus,
    required this.confirmed,
    required this.startWindowFrom,
    required this.startWindowTo,
    required this.addedCount,
    required this.removedCount,
    required this.ackRequired,
    this.roleInRun,
    this.confirmAt,
  });

  factory ManagerRun.fromJson(Map<String, dynamic> json) {
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
      estDurationMin: json['est_duration_min'] as int,
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
      roleInRun: UserRole.fromWireValueOrNull(json['role_in_run'] as String),
    );
  }

  final String runId;

  /// 호차.
  final String busNo;
  final RunDirection direction;
  final DateTime departTime;
  final String origin;
  final String destination;
  final int estDurationMin;
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

  /// 노선 변경 확인 응답 미완료 여부(RUN-07, §4.11 — 이번 라운드 범위 밖).
  final bool ackRequired;

  /// `null` 이면 서버가 이 앱이 모르는 역할을 줬다는 뜻 — 화면 구성은
  /// `roleCapabilitiesProvider`(로그인 시점 값)를 따로 쓰므로 이 필드
  /// 자체가 화면 분기에 쓰이지는 않는다.
  final UserRole? roleInRun;
}
