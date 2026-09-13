import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';

/// §4.3 실시간 노선 조회 — RouteMapScreen 전용 provider. `runId` 가 없으면
/// (진입 전) 곧바로 실패시켜 "선택된 운행 없음"과 "서버 응답 없음"을
/// 구분한다(`rosterProvider` 와 같은 패턴).
///
/// `manager_run_channel.dart` 의 실시간 이벤트(승하차 변경·도착·운행
/// 시작/종료)가 오면 이 provider 를 무효화해 다시 조회한다 — 지도는 그
/// 값을 그리는 자리일 뿐 별도로 값을 받지 않는다.
final routeProvider = FutureProvider<RouteResponse>((ref) {
  final runId = ref.watch(selectedRunIdProvider);
  if (runId == null) {
    throw StateError('선택된 운행이 없습니다');
  }
  return ref.watch(routeRepositoryProvider).fetchRoute(runId);
});
