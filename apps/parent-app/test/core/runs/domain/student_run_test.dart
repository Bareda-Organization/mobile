import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/common/run_direction.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';

/// §3.5 응답 파싱 시험 — 서버가 실제로 보내는 필드명(`snake_case`)과
/// enum 와이어 값이 어긋나면 여기서 잡힌다.
void main() {
  Map<String, dynamic> validJson() => {
    'run_id': 'run-1',
    'direction': 'to_academy',
    'bus_no': '1호차',
    'depart_time': '2026-09-12T08:00:00Z',
    'run_status': 'confirmed',
    'confirmed': true,
    'riding': true,
    'rider_status': 'waiting',
    'stop': {'stop_id': 'stop-1', 'name': '중앙 정류장', 'address': null},
    'change_quota_left': 1,
  };

  test('StudentRun.fromJson 은 서버 필드를 정확히 매핑한다', () {
    final run = StudentRun.fromJson(validJson());

    expect(run.runId, 'run-1');
    expect(run.direction, RunDirection.toAcademy);
    expect(run.busNo, '1호차');
    expect(run.runStatus, RunStatus.confirmed);
    expect(run.confirmed, isTrue);
    expect(run.riding, isTrue);
    expect(run.riderStatus, RiderStatus.waiting);
    expect(run.stop.stopId, 'stop-1');
    expect(run.changeQuotaLeft, 1);
  });

  test('RunStatus.fromWireValue 는 알 수 없는 값에 예외를 던진다', () {
    expect(
      () => RunStatus.fromWireValue('unknown_status'),
      throwsArgumentError,
    );
  });

  test('RiderStatus.fromWireValue 는 no_show 를 noShow 로 옮긴다', () {
    expect(RiderStatus.fromWireValue('no_show'), RiderStatus.noShow);
  });
}
