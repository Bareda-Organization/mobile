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
///
/// [log] 를 넘기면 재생 요청을 `'replay <경로>'` 로 적는다 — 즉시 전송
/// 클로저가 같은 목록에 적으면 **큐 재생과 새 요청의 선후**를 한 목록에서
/// 읽을 수 있다.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({List<String>? log}) : log = log ?? [];

  final List<RequestOptions> requests = [];
  final List<String> log;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    log.add('replay ${options.path}');
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

/// 통신이 아직 두절인 상태 — 재생 요청마다 연결 실패를 던진다.
class _OfflineAdapter implements HttpClientAdapter {
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
    throw DioException.connectionError(
      requestOptions: options,
      reason: '테스트 — 통신 두절',
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

  // M-06 "복구 시 자동 동기화" — 통신이 돌아온 것을 알리는 가장 이른 신호는
  // **쓰기 요청 한 건이 성공한 순간**이다. 그때 큐를 먼저 흘려보내지 않으면
  // 같은 학생의 옛 처리가 새 처리보다 **뒤에** 서버에 닿아 상태를 되돌린다
  // (오프라인에서 '탑승' → 복구 후 '되돌리기' → 재생이 '탑승' 을 덮어쓴다).
  test('큐에 쌓인 요청이 있으면 새 쓰기 요청보다 먼저 나간다', () async {
    final database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
    final log = <String>[];
    final adapter = _RecordingAdapter(log: log);
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = adapter;
    final repository = OfflineQueueRepositoryImpl(
      database: database,
      dio: dio,
    );

    await repository.sendOrQueue<void>(
      endpoint: '/runs/1/riders/7',
      method: 'PATCH',
      payload: const {'client_key': 'OLD', 'status': 'boarded'},
      // Failure 는 Exception/Error 를 상속하지 않는다 — 위 시험과 같은 이유.
      // ignore: only_throw_errors
      send: () => throw const Failure.network(),
    );
    expect(log, isEmpty, reason: '두절 중에는 아무것도 나가지 않는다');

    final outcome = await repository.sendOrQueue<void>(
      endpoint: '/runs/1/riders/9',
      method: 'PATCH',
      payload: const {'client_key': 'NEW', 'status': 'boarded'},
      send: () async => log.add('new /runs/1/riders/9'),
    );

    expect(outcome, isA<Sent<void>>());
    expect(log, ['replay /runs/1/riders/7', 'new /runs/1/riders/9']);
    expect(await repository.fetchPending(), isEmpty);

    await database.close();
  });

  // 두절이 이어지는 동안에는 큐에 쌓인 건수만큼 타임아웃을 기다리게 두지
  // 않는다 — 첫 실패에서 멈추고, 새 요청도 시도 없이 큐로 보낸다. 멈추지
  // 않으면 재생 중간 건이 성공·실패로 갈려 **큐 안의 순서마저 뒤집힌다.**
  test('아직 두절이면 재생은 첫 실패에서 멈추고 새 요청도 시도 없이 큐로 간다', () async {
    final database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
    final adapter = _OfflineAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = adapter;
    final repository = OfflineQueueRepositoryImpl(
      database: database,
      dio: dio,
    );

    for (final riderId in [7, 8]) {
      await repository.sendOrQueue<void>(
        endpoint: '/runs/1/riders/$riderId',
        method: 'PATCH',
        payload: {'client_key': 'KEY-$riderId', 'status': 'boarded'},
        // Failure 는 Exception/Error 를 상속하지 않는다 — 위 시험과 같은 이유.
        // ignore: only_throw_errors
        send: () => throw const Failure.network(),
      );
    }

    // 쌓는 동안에도 호출마다 재생을 한 번씩 시도한다(그때마다 첫 실패에서
    // 멈춘다) — 마지막 호출이 **몇 번 더** 시도하는지를 보려고 기준을 잡는다.
    final attemptsBefore = adapter.requests.length;
    var attempted = false;
    final outcome = await repository.sendOrQueue<void>(
      endpoint: '/runs/1/riders/9',
      method: 'PATCH',
      payload: const {'client_key': 'KEY-9', 'status': 'boarded'},
      send: () async => attempted = true,
    );

    expect(outcome, isA<Queued<void>>());
    expect(attempted, isFalse, reason: '두절이 확인됐으므로 새 요청은 시도하지 않는다');
    expect(
      adapter.requests.length - attemptsBefore,
      1,
      reason: '큐가 2건이어도 재생은 첫 실패에서 멈춘다',
    );
    expect(await repository.fetchPending(), hasLength(3));

    await database.close();
  });
}
