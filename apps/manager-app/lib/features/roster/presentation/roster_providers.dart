import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';

/// §4.2 명단 조회 — StopRoster 화면 전용 provider. `drive_mode_providers.dart`
/// 의 `driveModeRosterProvider` 와 같은 엔드포인트를 부르지만 별도로 뒀다 —
/// 두 화면은 새로고침 시점이 다르다(DriveMode 는 도착 처리 직후, StopRoster
/// 는 승하차 처리 직후). 조회 결과 캐시를 공유하는 편이 나을 수 있어
/// 승격 후보로 보고서에 남긴다.
final rosterProvider = FutureProvider<RosterResponse>((ref) {
  final runId = ref.watch(selectedRunIdProvider);
  if (runId == null) {
    throw StateError('선택된 운행이 없습니다');
  }
  return ref.watch(rosterRepositoryProvider).fetchRoster(runId);
});

/// [selectedRunIdProvider] 가 가리키는 회차 —
/// `drive_mode_providers.dart` 의 `driveModeRunProvider` 와 같은 패턴.
/// 별도 "회차 상세 조회" API 를 새로 만들지 않고 ManagerHome 이 이미 받아
/// 둔 §4.1 목록(`todayRunsProvider`)을 재사용한다. 두 provider 가 같은
/// 로직을 반복하고 있어 `core/run/` 로 승격할 후보로 보고서에 남긴다.
///
/// §4.11 배너 노출은 이 값의 `ackRequired`(RUN-07, §4.1 필드)를 근거로
/// 삼는다 — §4.2 로스터 응답에는 이 필드가 없어(스키마에 없음), 초기
/// 구현은 `stops[].change`·`students[].change` 존재 여부로 대신
/// 추론했었다. **정정**: §4.1 스키마를 다시 확인한 결과 `ack_required` 가
/// 이미 있어 그 추론은 불필요했다 — 이 provider 로 그 값을 직접 쓴다.
final selectedManagerRunProvider = Provider<ManagerRun?>((ref) {
  final runId = ref.watch(selectedRunIdProvider);
  final runs = ref.watch(todayRunsProvider).value;
  if (runId == null || runs == null) return null;
  for (final run in runs) {
    if (run.runId == runId) return run;
  }
  return null;
});
