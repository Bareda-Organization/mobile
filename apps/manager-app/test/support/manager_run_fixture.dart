import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';

/// 화면 시험이 쓰는 회차 한 건 — 필요한 값만 바꾸고 나머지는 같은 기본값을 쓴다.
ManagerRun managerRunFixture({
  String runId = 'run-1',
  String busNo = '3호차',
  RunStatus status = RunStatus.confirmed,
  bool confirmed = true,
  RunDirection direction = RunDirection.toAcademy,
  DateTime? departTime,
  bool ackRequired = false,
  UserRole? roleInRun,
  int addedCount = 0,
  int removedCount = 0,
  int? riderCount,
  int? absentCount,
  int? stopCount,
  int? estDurationMin = 30,
  String? plateNo,
  DateTime? startWindowFrom,
  DateTime? startWindowTo,
}) {
  final depart = departTime ?? DateTime(2026, 9, 30, 8);
  return ManagerRun(
    runId: runId,
    busNo: busNo,
    direction: direction,
    departTime: depart,
    origin: '기점',
    destination: '학원',
    estDurationMin: estDurationMin,
    runStatus: status,
    confirmed: confirmed,
    startWindowFrom:
        startWindowFrom ?? depart.subtract(const Duration(minutes: 10)),
    startWindowTo: startWindowTo ?? depart.add(const Duration(minutes: 10)),
    addedCount: addedCount,
    removedCount: removedCount,
    ackRequired: ackRequired,
    roleInRun: roleInRun,
    riderCount: riderCount,
    absentCount: absentCount,
    stopCount: stopCount,
    plateNo: plateNo,
  );
}
