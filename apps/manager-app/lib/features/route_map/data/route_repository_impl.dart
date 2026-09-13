import 'package:manager_app/core/network/guard.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/data/route_api.dart';
import 'package:manager_app/features/route_map/domain/route_repository.dart';

/// [RouteRepository] 구현 — `guardDio` 로 `DioException` 을 `Failure` 로
/// 옮긴다. 조회 전용이라 오프라인 큐를 거치지 않는다(§1.7 M-06 대상은
/// 승하차 처리뿐 — `RosterRepositoryImpl` 문서 주석 참고).
class RouteRepositoryImpl implements RouteRepository {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(RosterRepositoryImpl 과 같은 이유).
  const RouteRepositoryImpl({required RouteApi api})
    // 위와 같은 이유.
    // ignore: prefer_initializing_formals
    : _api = api;

  final RouteApi _api;

  @override
  Future<RouteResponse> fetchRoute(String runId) =>
      guardDio(() => _api.fetchRoute(runId));
}
