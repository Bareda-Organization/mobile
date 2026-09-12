import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/emergency/data/models/emergency_item.dart';

/// §4.15 비상 알림 이력 조회 — EmergencyScreen 전용 provider.
/// `roster_providers.dart` 의 `rosterProvider` 와 같은 패턴(선택된 회차가
/// 없으면 `StateError`, 있으면 저장소를 그대로 위임)이다.
///
/// 갱신은 화면 진입(최초 watch) + 수동 새로고침(`ref.invalidate`)뿐이다 —
/// 실시간 반영(WS `emergency_acked`)은 F4 범위라 이번 라운드는 두지 않는다.
final emergencyListProvider = FutureProvider<EmergencyListResponse>((ref) {
  final runId = ref.watch(selectedRunIdProvider);
  if (runId == null) {
    throw StateError('선택된 운행이 없습니다');
  }
  return ref.watch(emergencyRepositoryProvider).fetchList(runId: runId);
});
