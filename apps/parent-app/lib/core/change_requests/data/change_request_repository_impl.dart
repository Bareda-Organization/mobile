import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
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
  }) => _guard(
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
      _guard(() => _changeRequestApi.getChangeRequests(studentId));

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
