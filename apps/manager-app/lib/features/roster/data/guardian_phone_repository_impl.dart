import 'package:manager_app/core/network/guard.dart';
import 'package:manager_app/features/roster/data/roster_api.dart';
import 'package:manager_app/features/roster/domain/guardian_phone_repository.dart';

/// [GuardianPhoneRepository] 구현 — `guardDio` 로 `DioException` 을
/// `Failure` 로 옮긴다.
class GuardianPhoneRepositoryImpl implements GuardianPhoneRepository {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(RosterRepositoryImpl 과 같은 이유).
  // ignore: prefer_initializing_formals
  const new({required RosterApi api}) : _api = api;

  final RosterApi _api;

  @override
  Future<String?> fetchGuardianPhone({
    required String runId,
    required String riderId,
  }) => guardDio(() => _api.fetchGuardianPhone(runId: runId, riderId: riderId));
}
