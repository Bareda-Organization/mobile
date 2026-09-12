import 'package:manager_app/core/network/guard.dart';
import 'package:manager_app/features/delay/data/delay_api.dart';
import 'package:manager_app/features/delay/data/models/delay_request.dart';
import 'package:manager_app/features/delay/data/models/delay_result.dart';
import 'package:manager_app/features/delay/domain/delay_repository.dart';

/// [DelayRepository] 구현 — `guardDio` 로 `DioException` 을 `Failure` 로
/// 옮긴다.
class DelayRepositoryImpl implements DelayRepository {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(AuthRepositoryImpl 과 같은 이유).
  // ignore: prefer_initializing_formals
  const DelayRepositoryImpl({required DelayApi api}) : _api = api;

  final DelayApi _api;

  @override
  Future<DelayResult> sendDelay({
    required String runId,
    required DelayRequest request,
  }) => guardDio(() => _api.sendDelay(runId: runId, request: request));
}
