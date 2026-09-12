import 'package:manager_app/core/network/guard.dart';
import 'package:manager_app/features/position/data/models/position_request.dart';
import 'package:manager_app/features/position/data/position_api.dart';
import 'package:manager_app/features/position/domain/position_repository.dart';

/// [PositionRepository] 구현 — `guardDio` 로 `DioException` 을 `Failure` 로
/// 옮긴다.
class PositionRepositoryImpl implements PositionRepository {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(DelayRepositoryImpl 과 같은 이유).
  // ignore: prefer_initializing_formals
  const PositionRepositoryImpl({required PositionApi api}) : _api = api;

  final PositionApi _api;

  @override
  Future<void> sendPosition({
    required String runId,
    required PositionRequest request,
  }) => guardDio(() => _api.sendPosition(runId: runId, request: request));
}
