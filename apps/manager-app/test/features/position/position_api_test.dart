import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/core/constants/position_constants.dart';
import 'package:manager_app/features/position/data/models/position_request.dart';
import 'package:manager_app/features/position/data/position_api.dart';

/// 나간 요청의 옵션을 기록하는 어댑터 — 요청별 시간 제한이 실제로 실렸는지 본다.
class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString('', 204);
  }
}

/// R46-FIXCONN C-7 — 위치 POST 는 공용 Dio 설정(송신 15초·응답 30초)을 그대로
/// 써서, 음영에서 나간 요청이 30초 걸려서야 실패했고 그동안 다음 위치를 못
/// 보냈다(앞 요청이 안 끝나면 주기를 건너뛴다). 위치는 2초 주기라 5초 넘는
/// 요청은 가치가 없다.
void main() {
  test('위치 POST 는 요청별로 송신 4초·응답 5초 한도를 가진다', () async {
    final adapter = _RecordingAdapter();
    // 공용 설정(느슨한 값)을 흉내 낸 기본 Dio — 요청별 값이 이것을 이겨야 한다.
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.invalid',
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    )..httpClientAdapter = adapter;

    await PositionApi(dio: dio).sendPosition(
      runId: '1',
      request: PositionRequest(
        lat: 37.5,
        lng: 127,
        recordedAt: DateTime.utc(2026, 10, 1, 9),
      ),
    );

    expect(adapter.requests, hasLength(1));
    expect(
      adapter.requests.single.sendTimeout,
      PositionConstants.requestSendTimeout,
    );
    expect(
      adapter.requests.single.receiveTimeout,
      PositionConstants.requestReceiveTimeout,
    );
    expect(PositionConstants.requestSendTimeout, const Duration(seconds: 4));
    expect(PositionConstants.requestReceiveTimeout, const Duration(seconds: 5));
  });
}
