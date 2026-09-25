import 'package:baraeda_core/baraeda_core.dart';
import 'package:manager_app/core/run/run_enums.dart';

/// 승하차지 정류장 `change` 표시 — §4.2. `added`(초록) · `skipped`(빨강
/// 취소선, 순번 유지). 값이 없으면 변경 없음.
enum StopChange {
  added('added'),
  skipped('skipped');

  const StopChange(this.wireValue);

  final String wireValue;

  static StopChange? fromWireValueOrNull(String? value) {
    for (final change in StopChange.values) {
      if (change.wireValue == value) return change;
    }
    return null;
  }
}

/// 탑승자별 `change` 표시(added·removed) — 정류장의 [StopChange] 와 별개 값.
enum RiderChange {
  added('added'),
  removed('removed');

  const RiderChange(this.wireValue);

  final String wireValue;

  static RiderChange? fromWireValueOrNull(String? value) {
    for (final change in RiderChange.values) {
      if (change.wireValue == value) return change;
    }
    return null;
  }
}

/// `no_show_case` — §4.2·§4.6. `expires_at` 은 3분 카운트다운 만료 시각을
/// 절대 시각으로 표시한다(core/run/run_enums.dart 주석 · Clock 미도입 판단
/// 근거 참고, 보고서에 기록).
class NoShowCase {
  const NoShowCase({
    required this.caseId,
    required this.startedAt,
    required this.expiresAt,
  });

  factory NoShowCase.fromJson(Map<String, dynamic> json) {
    return NoShowCase(
      caseId: json['case_id'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  final String caseId;
  final DateTime startedAt;
  final DateTime expiresAt;
}

/// `stops[].students[]` 항목 — §4.2.
class RosterStudent {
  const RosterStudent({
    required this.riderId,
    required this.studentId,
    required this.name,
    required this.photoUrl,
    required this.guardianPhone,
    required this.canGoAlone,
    required this.status,
    this.className,
    this.note,
    this.change,
    this.noShowCase,
  });

  factory RosterStudent.fromJson(Map<String, dynamic> json) {
    final noShowCaseJson = json['no_show_case'] as Map<String, dynamic>?;
    return RosterStudent(
      // `Ruling 275` — 서버가 rider_id 를 int 로 내려도 흡수한다(직접 캐스트 금지).
      riderId: asIdString(json['rider_id']),
      studentId: json['student_id'] as String,
      name: json['name'] as String,
      // §4.2(2026-09-14 확정) — 미등록 학생이 예외가 아니라 기본 상태라
      // 서버가 `photo_url: null` 을 내려보낸다. `StudentRow`(baraeda_ui)
      // 가 이 값을 받아 렌더하고, 없거나 로드에 실패하면 이름 이니셜로
      // 대체한다(`R4 A-photo` — roster_screen.dart 가 그대로 전달).
      photoUrl: json['photo_url'] as String?,
      className: json['class_name'] as String?,
      // 마스킹은 서버가 이미 적용(`010-2XXX-8814`) — 클라이언트는 그대로 표시.
      // 보호자 미연결 학생은 `null`(§4.2 `○`, BR-082) — 화면은 연락처 칸을 생략한다.
      guardianPhone: json['guardian_phone'] as String?,
      note: json['note'] as String?,
      canGoAlone: json['can_go_alone'] as bool,
      status:
          RiderStatus.fromWireValueOrNull(json['status'] as String?) ??
          RiderStatus.waiting,
      change: RiderChange.fromWireValueOrNull(json['change'] as String?),
      noShowCase: noShowCaseJson == null
          ? null
          : NoShowCase.fromJson(noShowCaseJson),
    );
  }

  final String riderId;
  final String studentId;
  final String name;
  final String? photoUrl;
  final String? className;
  final String? guardianPhone;
  final String? note;
  final bool canGoAlone;
  final RiderStatus status;
  final RiderChange? change;
  final NoShowCase? noShowCase;
}

/// `stops[]` 항목 — §4.2.
class RosterStop {
  const RosterStop({
    required this.stopId,
    required this.seq,
    required this.name,
    required this.students,
    this.address,
    this.change,
    this.skipNotice,
    this.arrivedAt,
  });

  factory RosterStop.fromJson(Map<String, dynamic> json) {
    final studentsJson = json['students'] as List<dynamic>? ?? [];
    final arrivedAtRaw = json['arrived_at'] as String?;
    return RosterStop(
      // `Ruling 275` — 서버가 stop_id 를 int 로 내려도 흡수한다(직접 캐스트 금지).
      stopId: asIdString(json['stop_id']),
      seq: json['seq'] as int,
      name: json['name'] as String,
      address: json['address'] as String?,
      change: StopChange.fromWireValueOrNull(json['change'] as String?),
      skipNotice: json['skip_notice'] as String?,
      arrivedAt: arrivedAtRaw == null ? null : DateTime.parse(arrivedAtRaw),
      students: studentsJson
          .cast<Map<String, dynamic>>()
          .map(RosterStudent.fromJson)
          .toList(),
    );
  }

  final String stopId;
  final int seq;
  final String name;
  final String? address;
  final StopChange? change;
  final String? skipNotice;
  final DateTime? arrivedAt;
  final List<RosterStudent> students;
}

/// `counts` — §4.2. `absentN` 은 개인 행에서 제외된 결석자 집계(RST-02·04).
class RosterCounts {
  const RosterCounts({
    required this.boarded,
    required this.waiting,
    required this.noShow,
    required this.absentN,
  });

  factory RosterCounts.fromJson(Map<String, dynamic> json) {
    return RosterCounts(
      boarded: json['boarded'] as int,
      waiting: json['waiting'] as int,
      noShow: json['no_show'] as int,
      absentN: json['absent_n'] as int,
    );
  }

  final int boarded;
  final int waiting;
  final int noShow;
  final int absentN;
}

/// `GET /runs/{runId}/roster` 응답 전체 — §4.2.
class RosterResponse {
  const RosterResponse({
    required this.runId,
    required this.busNo,
    required this.direction,
    required this.counts,
    required this.stops,
  });

  factory RosterResponse.fromJson(Map<String, dynamic> json) {
    final stopsJson = json['stops'] as List<dynamic>? ?? [];
    return RosterResponse(
      runId: json['run_id'] as String,
      busNo: json['bus_no'] as String,
      direction:
          RunDirection.fromWireValueOrNull(json['direction'] as String?) ??
          RunDirection.toAcademy,
      counts: RosterCounts.fromJson(json['counts'] as Map<String, dynamic>),
      stops: stopsJson
          .cast<Map<String, dynamic>>()
          .map(RosterStop.fromJson)
          .toList(),
    );
  }

  final String runId;
  final String busNo;
  final RunDirection direction;
  final RosterCounts counts;
  final List<RosterStop> stops;
}
