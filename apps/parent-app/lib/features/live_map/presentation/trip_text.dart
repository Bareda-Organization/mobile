import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/core/runs/presentation/run_display.dart';

/// 이 회차가 가는 곳의 이름 — 등원은 학원 이름(`/me` 의 `academy.name`), 하원은 내 승하차지 이름(`Ruling 832`).
///
/// 방향을 모르거나(회차 목록을 못 받음) 그 방향의 이름을 못 얻으면 `null` 이다 — **다른 쪽 이름으로 채우지 않는다**
/// (등원인데 내 승하차지 이름을 "도착지" 로 쓰면 거짓이다). `null` 이면 아래 문구는 R48 의 이름 없는 모양으로 떨어진다.
String? tripDestination({
  required RunDirection? direction,
  required String? academyName,
  required String? myStopName,
}) => switch (direction) {
  RunDirection.toAcademy => academyName,
  RunDirection.fromAcademy => myStopName,
  null => null,
};

/// 시트 이름 아래 줄 — 운행 중 `하늘수학 가는 길 · 12:05 운행 시작`, 종료 `하늘수학 도착`.
/// 이름이 없으면 운행 중은 `12:05 운행 시작`, 종료는 줄이 없다. 있는 조각만 ` · ` 로 잇는다.
String? sheetSubtitle({
  required bool ended,
  required String? destination,
  required DateTime? startedAt,
}) {
  if (ended) return destination == null ? null : '$destination 도착';
  final parts = [
    if (destination != null) '$destination 가는 길',
    if (startedAt != null) '${formatClock(startedAt)} 운행 시작',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// 종료 띠 본문 — `12:52 하늘수학에 도착했어요.`. 이름이 없으면 R48 문구 `12:52 에 운행을 마쳤어요.`,
/// 종료 시각도 모르면 이름만(`하늘수학에 도착했어요.`), 둘 다 없으면 본문이 없다.
String? endedBody({
  required DateTime? finishedAt,
  required String? destination,
}) {
  if (destination == null) {
    return finishedAt == null ? null : '${formatClock(finishedAt)} 에 운행을 마쳤어요.';
  }
  final arrived = '$destination에 도착했어요.';
  return finishedAt == null ? arrived : '${formatClock(finishedAt)} $arrived';
}
