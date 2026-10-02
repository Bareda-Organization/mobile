import 'package:dio/dio.dart';
import 'package:manager_app/core/constants/position_constants.dart';
import 'package:manager_app/features/position/data/models/position_request.dart';

/// API_SPEC §4.12.
class PositionApi {
  // 필드를 private 으로 유지하려고 initializing formal 대신 명시 대입을
  // 쓴다(DelayApi 와 같은 이유).
  // ignore: prefer_initializing_formals
  new({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<void> sendPosition({
    required String runId,
    required PositionRequest request,
  }) async {
    await _dio.post<void>(
      '/runs/$runId/position',
      data: request.toJson(),
      // 위치는 2초 주기라 오래 기다릴 가치가 없다 — 공용 Dio 설정(송신 15초·응답 30초)보다 짧은 요청별 한도.
      options: Options(
        sendTimeout: PositionConstants.requestSendTimeout,
        receiveTimeout: PositionConstants.requestReceiveTimeout,
      ),
    );
  }
}
