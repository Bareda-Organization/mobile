import 'package:manager_app/features/route_map/data/models/route_response.dart';

/// §4.3 실시간 노선 조회(기사·동승자 둘 다 호출 가능). 조회 전용이라
/// `RosterRepository` 와 달리 쓰기 메서드가 없다.
// 메서드가 하나뿐이지만 `di.dart` 의 Provider<XRepository> 조립 지점과
// 맞추려 인터페이스로 둔다(DelayRepository 등 한 메서드짜리와 같은 패턴).
abstract interface class RouteRepository {
  Future<RouteResponse> fetchRoute(String runId);
}
