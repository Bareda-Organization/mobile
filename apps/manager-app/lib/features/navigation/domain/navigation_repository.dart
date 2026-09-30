import 'package:manager_app/features/navigation/data/models/navigation_route.dart';

// 메서드가 하나뿐이지만 `di.dart` 의 Provider<XRepository> 조립 지점과 맞추려 인터페이스로 둔다
// (RouteRepository 와 같은 패턴).
// ignore: one_member_abstracts
abstract interface class NavigationRepository {
  /// 외부 내비에 넘길 남은 경로(§4.16).
  Future<NavigationRoute> fetchRemaining(String runId);
}
