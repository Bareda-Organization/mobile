import 'package:baraeda_core/baraeda_core.dart';
import 'package:parent_app/core/runs/domain/bus_position.dart';
import 'package:parent_app/features/live_map/data/bus_position_api.dart';
import 'package:parent_app/features/live_map/domain/bus_position_repository.dart';

class BusPositionRepositoryImpl implements BusPositionRepository {
  const new({required this._busPositionApi});
  final BusPositionApi _busPositionApi;

  @override
  Future<BusPosition> getBusPosition(String studentId) =>
      guardDio(() => _busPositionApi.getBusPosition(studentId));
}
