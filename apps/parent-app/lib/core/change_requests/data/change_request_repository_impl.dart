import 'package:baraeda_core/baraeda_core.dart';
import 'package:parent_app/core/change_requests/data/change_request_api.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/change_requests/domain/change_request_repository.dart';

class ChangeRequestRepositoryImpl implements ChangeRequestRepository {
  const new({required this._changeRequestApi});

  final ChangeRequestApi _changeRequestApi;

  @override
  Future<ChangeRequestCreateResult> createChangeRequest(
    String studentId, {
    required ChangeRequestType type,
    required String runId,
    String? newAddress,
    String? reason,
  }) => guardDio(
    () => _changeRequestApi.createChangeRequest(
      studentId,
      type: type,
      runId: runId,
      newAddress: newAddress,
      reason: reason,
    ),
  );

  @override
  Future<ChangeRequestPage> getChangeRequests(String studentId) =>
      guardDio(() => _changeRequestApi.getChangeRequests(studentId));
}
