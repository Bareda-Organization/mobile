import 'dart:typed_data';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_repository_impl.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';

/// 실제 소켓을 열지 않고 `replayPending()` 이 보내는 요청을 그대로
/// 가로채는 가짜 어댑터 — 서버로 나간 본문(`RequestOptions.data`)을
/// 그대로 기록해 둔다.
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
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  // API_SPEC §1.7 의 핵심 계약 — "즉시 전송이 실패해 큐에 쌓인 요청을 나중에
  // 재생할 때, 서버로 나가는 client_key 가 최초 시도 때와 같은 값이어야
  // 한다"를 리포지토리 계층에서 직접 검사한다. 이 계약이 깨지면 서버가
  // 재생분을 새 요청으로 오인해 같은 비상 발신·승하차 처리가 중복된다.
  test('큐 재생이 즉시 전송과 같은 client_key 를 그대로 다시 보낸다', () async {
    final database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
    final adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = adapter;
    final repository = OfflineQueueRepositoryImpl(
      database: database,
      dio: dio,
    );

    const originalClientKey = 'ORIGINAL-CLIENT-KEY';
    final outcome = await repository.sendOrQueue<void>(
      clientKey: originalClientKey,
      endpoint: '/runs/1/emergency',
      method: 'POST',
      payload: const {'client_key': originalClientKey, 'type': 'etc'},
      // 즉시 전송이 통신 두절로 실패했다고 가정 — sendOrQueue 는 이
      // NetworkFailure 를 잡아 큐에 쌓아야 한다. Failure 는 의도적으로
      // Exception/Error 를 상속하지 않는다(emergency_screen_test.dart 와
      // 같은 패턴).
      // ignore: only_throw_errors
      send: () => throw const Failure.network(),
    );
    expect(outcome, isA<Queued<void>>());

    await repository.replayPending();

    expect(adapter.requests, hasLength(1));
    final replayedBody = adapter.requests.single.data as Map<String, dynamic>;
    expect(replayedBody['client_key'], originalClientKey);

    await database.close();
  });
}
