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

/// 서버가 응답은 했지만 [status] 로 거절·실패한 상태 — 본문은 [body] 그대로.
class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.status, this.body);

  final int status;
  final String body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
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

  // R46 — 같은 학생에게 같은 승하차 처리를 두 번 누르면 큐에 두 줄이 쌓여 재생 때 같은 처리가 두 번 나간다.
  test('같은 학생·같은 승하차 처리는 큐에 한 번만 쌓는다', () async {
    final database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = _OfflineAdapter();
    final repository = OfflineQueueRepositoryImpl(
      database: database,
      dio: dio,
    );

    Future<SendOutcome<void>> press(
      String riderId,
      String status,
      String key,
    ) => repository.sendOrQueue<void>(
      endpoint: '/runs/1/riders/$riderId',
      method: 'PATCH',
      payload: {'status': status, 'client_key': key},
      // ignore: only_throw_errors
      send: () => throw const Failure.network(),
    );

    expect(await press('7', 'boarded', 'k1'), isA<Queued<void>>());
    expect(await press('7', 'boarded', 'k2'), isA<Queued<void>>());
    await press('7', 'no_show', 'k3');
    await press('8', 'boarded', 'k4');

    final pending = await repository.fetchPending();
    expect(pending.map((row) => '${row.endpoint} ${row.payload}').toList(), [
      contains('/runs/1/riders/7'),
      contains('/runs/1/riders/7'),
      contains('/runs/1/riders/8'),
    ]);
    expect(
      pending.map((row) => row.description).toList(),
      ['탑승 처리', '미승차 처리', '탑승 처리'],
      reason: '같은 학생의 다른 처리·다른 학생의 같은 처리는 각각 쌓인다',
    );

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

  // F06-01 — 서버가 응답했다고 전부 "확정 거부" 가 아니다. 재시도하면 통과할
  // 수 있는 응답(5xx·429·401·비JSON 프록시 오류)은 행을 남겨야 하고, 재시도해도
  // 같은 결과인 4xx 검증·권한 거절만 뺀다.
  const errorEnvelope = '{"error":{"code":"X","message":"m"}}';
  const cases = <(String, int, String, bool)>[
    ('502 비JSON(프록시 재시작)', 502, '<html>Bad Gateway</html>', true),
    ('503 비JSON', 503, 'upstream down', true),
    ('500 JSON 봉투', 500, errorEnvelope, true),
    ('429 요청 과다', 429, errorEnvelope, true),
    ('401 인증 만료', 401, errorEnvelope, true),
    ('422 검증 실패', 422, errorEnvelope, false),
    ('409 상태 충돌', 409, errorEnvelope, false),
    ('403 권한 없음', 403, errorEnvelope, false),
  ];
  for (final (name, status, body, keep) in cases) {
    test('재생 중 $name 응답이면 행을 ${keep ? '남기고 재시도 대기로 센다' : '제외한다'}', () async {
      final database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
        ..httpClientAdapter = _StatusAdapter(status, body);
      final repository = OfflineQueueRepositoryImpl(
        database: database,
        dio: dio,
      );
      await repository.sendOrQueue<void>(
        endpoint: '/runs/1/riders/7',
        method: 'PATCH',
        payload: const {'client_key': 'K', 'status': 'boarded'},
        // Failure 는 Exception/Error 를 상속하지 않는다 — 위 시험과 같은 이유.
        // ignore: only_throw_errors
        send: () => throw const Failure.network(),
      );

      final result = await repository.replayPending();

      expect(await repository.fetchPending(), hasLength(keep ? 1 : 0));
      expect(result.stillPending, keep ? 1 : 0);
      expect(result.droppedPermanently, keep ? 0 : 1);

      await database.close();
    });
  }

  test('cancel 은 그 행만 큐에서 지운다', () async {
    final database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
    final repository = OfflineQueueRepositoryImpl(
      database: database,
      dio: Dio(BaseOptions(baseUrl: 'https://example.invalid'))
        ..httpClientAdapter = _OfflineAdapter(),
    );
    for (final riderId in [7, 8]) {
      await repository.sendOrQueue<void>(
        endpoint: '/runs/1/riders/$riderId',
        method: 'PATCH',
        payload: {'client_key': 'K$riderId', 'status': 'boarded'},
        // Failure 는 Exception/Error 를 상속하지 않는다 — 위 시험과 같은 이유.
        // ignore: only_throw_errors
        send: () => throw const Failure.network(),
      );
    }
    final pending = await repository.fetchPending();
    expect(pending, hasLength(2));

    await repository.cancel(pending.first.id);

    final rest = await repository.fetchPending();
    expect(rest.map((item) => item.id), [pending.last.id]);
    expect(rest.single.payload, contains('K8'));

    await database.close();
  });
}
