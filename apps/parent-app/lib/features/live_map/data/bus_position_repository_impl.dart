import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:parent_app/features/live_map/data/bus_position_api.dart';
import 'package:parent_app/core/runs/domain/bus_position.dart';
import 'package:parent_app/features/live_map/domain/bus_position_repository.dart';

class BusPositionRepositoryImpl implements BusPositionRepository {
  const new({required this._busPositionApi});
  final BusPositionApi _busPositionApi;

  @override
  Future<BusPosition> getBusPosition(String studentId) =>
      _guard(() => _busPositionApi.getBusPosition(studentId));

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on DioException catch (exception) {
      // Failure 는 의도적으로 Exception/Error 를 상속하지 않는다
      // (auth_repository_impl.dart 와 같은 설계 — dart:core 예외 체계를
      // 흉내 내지 않는다). 이 지점의 `only_throw_errors` 는 예외로 둔다.
      // ignore: only_throw_errors
      throw mapDioExceptionToFailure(exception);
    }
  }
}
