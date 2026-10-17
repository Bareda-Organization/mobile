import 'package:baraeda_core/baraeda_core.dart';
import 'package:parent_app/core/routes/domain/route_detail.dart';
import 'package:parent_app/core/routes/domain/route_repository.dart';
import 'package:parent_app/features/route/data/route_api.dart';

class RouteRepositoryImpl implements RouteRepository {
  const new({required this._routeApi});

  final RouteApi _routeApi;

  @override
  Future<RouteDetail> getRoute(
    String studentId, {
    DateTime? date,
    String? runId,
  }) => guardDio(() => _routeApi.getRoute(studentId, date: date, runId: runId));
}
