import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/ui/format_date_time.dart';

/// 회차 표시 문구·상태 칩 — 홈 카드(`RunCard`)와 일정 탭이 같은 말을 쓴다.

/// 서버가 주는 시각은 **UTC 순간**이다(`…Z`). `DateTime.parse` 는 오프셋이 붙은 문자열을 UTC
/// `DateTime` 으로
/// 돌려주므로, 벽시계로 읽으려면 기기 표준시로 옮겨야 한다 — 안 옮기면 KST 에서 **9시간 이른 시각**이 나온다.
String formatClock(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// 확정(출발 30분 전)까지 남은 시간 문구 — 확정 전(`idle`·미확정)이고 아직 남았을 때만.
String? untilConfirm(StudentRun run, DateTime now) {
  if (run.runStatus != RunStatus.idle || run.confirmed) return null;
  final left = run.departTime
      .subtract(const Duration(minutes: 30))
      .difference(now);
  return left <= Duration.zero ? null : formatRemaining(left);
}

/// 회차 한 건의 상태 칩 — 탑승 결과가 있으면 그것이, 없으면 운행 진행이 정한다.
({BaraedaStatus status, String label}) runStatusChip(StudentRun run) {
  return switch (run.riderStatus) {
    RiderStatus.boarded || RiderStatus.alighted => (
      status: BaraedaStatus.boarded,
      label: run.riderStatus == RiderStatus.boarded ? '탑승 완료' : '하차 완료',
    ),
    // ⚠ `absent`(미등원)와 `no_show`(미승차)를 합치지 않는다 — `FEATURE_SPEC C-02`
    // 가 "반드시 구분" 을 명시한다. 학부모에게 둘은 전혀 다른 일이다 —
    // 미등원은 **내가 직접 껐다**(정상), 미승차는 **버스가 왔는데 안 나왔다**(사고).
    // 색도 사양이 가른다(§3 상태표) — 미등원 스톤 · 미승차 레드.
    RiderStatus.absent => (status: BaraedaStatus.idle, label: '미등원'),
    RiderStatus.noShow => (status: BaraedaStatus.missed, label: '미승차'),
    // 끝난 회차에 대기 값이 남아 있어도 "운행 전" 으로 읽히면 안 된다(R52 A12).
    RiderStatus.waiting => switch (run.runStatus) {
      RunStatus.moving => (status: BaraedaStatus.moving, label: '이동 중'),
      RunStatus.finished => (status: BaraedaStatus.idle, label: '종료'),
      RunStatus.idle ||
      RunStatus.confirmed => (status: BaraedaStatus.idle, label: '운행 전'),
    },
  };
}
