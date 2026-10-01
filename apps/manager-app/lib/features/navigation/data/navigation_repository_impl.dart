import 'package:manager_app/core/network/guard.dart';
import 'package:manager_app/features/navigation/data/models/navigation_route.dart';
import 'package:manager_app/features/navigation/data/models/navigation_scope.dart';
import 'package:manager_app/features/navigation/data/navigation_api.dart';
import 'package:manager_app/features/navigation/domain/navigation_repository.dart';

class NavigationRepositoryImpl implements NavigationRepository {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을 쓴다
  // (RouteRepositoryImpl 과 같은 이유).
  // ignore: prefer_initializing_formals
  const NavigationRepositoryImpl({required NavigationApi api}) : _api = api;

  final NavigationApi _api;

  @override
  Future<NavigationRoute> fetch(String runId, NavigationScope scope) =>
      guardDio(() => _api.fetch(runId, scope));
}
