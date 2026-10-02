import 'package:manager_app/core/network/guard.dart';
import 'package:manager_app/features/home/data/manager_run_api.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/domain/manager_run_repository.dart';

/// [ManagerRunRepository] 구현 — `ManagerRunApi` 를 감싸 `DioException` 을
/// `Failure` 로 옮긴다(`guardDio`, `AuthRepositoryImpl` 과 같은 패턴).
class ManagerRunRepositoryImpl implements ManagerRunRepository {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(AuthRepositoryImpl 과 같은 이유).
  // ignore: prefer_initializing_formals
  const new({required ManagerRunApi api}) : _api = api;

  final ManagerRunApi _api;

  @override
  Future<List<ManagerRun>> fetchRuns({DateTime? date}) =>
      guardDio(() => _api.fetchRuns(date: date));
}
