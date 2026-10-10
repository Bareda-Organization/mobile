import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/runs/presentation/run_display.dart';

StudentRun _run(RunStatus runStatus, RiderStatus riderStatus) => StudentRun(
  runId: 'run-1',
  direction: RunDirection.toAcademy,
  busNo: '1호차',
  departTime: DateTime.utc(2026, 10, 10, 8),
  runStatus: runStatus,
  confirmed: runStatus != RunStatus.idle,
  riding: true,
  riderStatus: riderStatus,
  stop: const RunStop(stopId: 'stop-1', name: '정문'),
  changeQuotaLeft: 1,
);

/// 회차 카드 상태 칩 — 홈 카드와 일정 탭이 같은 말을 쓴다.
void main() {
  // R52 `Ruling 871` — 서버가 출발 전 미승차(`no_show`)를 `waiting` 으로 보낸다.
  // 앱은 받은 값을 가공하지 않고 대기로 그린다 — 빨간 "미승차" 는 `no_show` 가
  // 올 때만 나온다.
  group('R52 871 출발 전에는 대기로 그린다', () {
    for (final runStatus in [RunStatus.idle, RunStatus.confirmed]) {
      test('waiting + ${runStatus.name} 는 "운행 전" 이고 빨간 표시가 아니다', () {
        final chip = runStatusChip(_run(runStatus, RiderStatus.waiting));

        expect(chip.label, '운행 전');
        expect(chip.status, isNot(BaraedaStatus.missed));
      });
    }

    test('no_show 가 오면 빨간 "미승차" 이다 — 출발 뒤의 서버 값은 그대로 그린다', () {
      final chip = runStatusChip(_run(RunStatus.moving, RiderStatus.noShow));

      expect(chip.label, '미승차');
      expect(chip.status, BaraedaStatus.missed);
    });
  });

  // R52 낮음 A12 — 끝난 회차에 대기 값이 남아 있으면 "운행 전" 으로 읽혔다.
  test('waiting + finished 는 "운행 전" 이 아니라 "종료" 다', () {
    final chip = runStatusChip(_run(RunStatus.finished, RiderStatus.waiting));

    expect(chip.label, '종료');
    expect(chip.status, BaraedaStatus.idle);
  });

  test('waiting + moving 은 "이동 중" 이다', () {
    final chip = runStatusChip(_run(RunStatus.moving, RiderStatus.waiting));

    expect(chip.label, '이동 중');
  });
}
