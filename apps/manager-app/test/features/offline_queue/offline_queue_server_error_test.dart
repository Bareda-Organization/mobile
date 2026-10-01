import 'dart:typed_data';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_repository_impl.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';

/// 경로마다 정해 둔 상태로 응답하는 가짜 어댑터 — 어느 경로가 몇 번 나갔는지 [paths] 에 남는다.
/// [statusOf] 가 `null` 이면 통신 두절(연결 실패)로 던진다.
class _PathAdapter implements HttpClientAdapter {
  _PathAdapter(this.statusOf);

  final int? Function(String path) statusOf;
  final List<String> paths = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    final status = statusOf(options.path);
    if (status == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: '테스트 — 통신 두절',
      );
    }
    return ResponseBody.fromString(
      '{"error":{"code":"X","message":"m"}}',
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

/// 시험이 시각을 고정하는 가짜 시계 — 큐 행의 나이 상한 판정에 쓴다.
class _FixedClock implements Clock {
  _FixedClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;
}

const _poisonPath = '/runs/1/riders/7';
const _healthyPath = '/runs/1/riders/8';

({
  OfflineQueueDatabase database,
  OfflineQueueRepositoryImpl repository,
  _PathAdapter adapter,
  _FixedClock clock,
})
_setup(int? Function(String path) statusOf) {
  final database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
  final adapter = _PathAdapter(statusOf);
  final clock = _FixedClock(DateTime.now());
  final repository = OfflineQueueRepositoryImpl(
    database: database,
    dio: Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = adapter,
    clock: clock,
  );
  return (
    database: database,
    repository: repository,
    adapter: adapter,
    clock: clock,
  );
}

/// 즉시 전송이 [failure] 로 실패한 것으로 보고 큐에 넣게 한다. 큐에 못 넣으면 그 Failure 가 그대로 올라온다.
Future<SendOutcome<void>> _press(
  OfflineQueueRepositoryImpl repository,
  String endpoint,
  Failure failure, {
  String method = 'PATCH',
  Map<String, dynamic>? payload,
}) => repository.sendOrQueue<void>(
  endpoint: endpoint,
  method: method,
  payload: payload ?? {'client_key': 'K-$endpoint', 'status': 'boarded'},
  // Failure 는 Exception/Error 를 상속하지 않는다 — 기존 시험과 같은 이유.
  // ignore: only_throw_errors
  send: () => throw failure,
);

Failure _api(int status) =>
    Failure.api(statusCode: status, code: 'X', message: 'm');

void main() {
  // S-9 ① — 서버가 응답은 했는데 못 받는 5xx 도 두절과 같다. 백엔드 재기동(nginx 502)·풀 고갈(500) 동안 누른
  // 승하차와 **비상 신고**가 큐에 남아야 한다. 재시도는 `client_key` 가 서버 중복을 막는다.
  final queued = <(String, Failure)>[
    ('500 JSON 봉투', _api(500)),
    ('502 JSON 봉투', _api(502)),
    ('503 JSON 봉투', _api(503)),
    ('504 JSON 봉투', _api(504)),
    ('502 nginx HTML', const Failure.unknown(statusCode: 502)),
    ('504 nginx HTML', const Failure.unknown(statusCode: 504)),
  ];
  for (final (name, failure) in queued) {
    test('즉시 전송이 $name 이면 승하차도 비상 신고도 큐에 쌓는다', () async {
      // 서버가 계속 5xx 인 상황 — 두 번째 누름 앞의 재생도 5xx 를 받아 첫 행이 큐에 남는다.
      final s = _setup((_) => 500);

      final rider = await _press(s.repository, _poisonPath, failure);
      final emergency = await _press(
        s.repository,
        '/runs/1/emergency',
        failure,
        method: 'POST',
        payload: {'client_key': 'K-E', 'type': 'etc'},
      );

      expect(rider, isA<Queued<void>>());
      expect(emergency, isA<Queued<void>>());
      expect((await s.repository.fetchPending()).map((e) => e.method), [
        'PATCH',
        'POST',
      ]);
      await s.database.close();
    });
  }

  // 다시 보내도 같은 응답인 오류까지 쌓으면 큐가 쓰레기로 찬다 — 호출부가 그대로 오류를 받아야 한다.
  final notQueued = <(String, Failure)>[
    ('422 검증 실패', _api(422)),
    ('409 상태 충돌', _api(409)),
    ('404 HTML', const Failure.unknown(statusCode: 404)),
    ('응답 없는 알 수 없는 오류(취소 등)', const Failure.unknown()),
    ('재로그인 필요', const Failure.unauthenticated()),
  ];
  for (final (name, failure) in notQueued) {
    test('즉시 전송이 $name 이면 큐에 쌓지 않고 오류를 그대로 올린다', () async {
      final s = _setup((_) => 200);

      await expectLater(
        _press(s.repository, _poisonPath, failure),
        throwsA(same(failure)),
      );

      expect(await s.repository.fetchPending(), isEmpty);
      await s.database.close();
    });
  }

  // S-9 ② — 결정적으로 500 을 받는 행이 큐 머리에서 뒤를 영구히 막지 않는다.
  group('재생 — 큐 머리의 한 행이 뒤를 막지 않는다', () {
    Future<
      ({
        OfflineQueueDatabase database,
        OfflineQueueRepositoryImpl repository,
        _PathAdapter adapter,
        _FixedClock clock,
      })
    >
    twoRows() async {
      // 7번 학생 처리는 언제나 500, 8번은 정상.
      final s = _setup((path) => path == _poisonPath ? 500 : 200);
      await _press(s.repository, _poisonPath, const Failure.network());
      await _press(s.repository, _healthyPath, const Failure.network());
      return s;
    }

    test('시도 상한(10회) 전까지는 머리 행이 남고 뒤 행은 순서를 지켜 기다린다', () async {
      final s = await twoRows();

      for (var i = 0; i < OfflineQueueRepositoryImpl.maxAttempts - 1; i++) {
        final result = await s.repository.replayPending();
        expect(result.stillPending, 2);
        expect(result.failedPermanently, 0);
      }

      expect(s.adapter.paths.toSet(), {_poisonPath}, reason: '뒤 행은 한 번도 안 나간다');
      await s.database.close();
    });

    test('시도 상한에 닿으면 머리 행을 영구 실패로 빼고 같은 재생에서 뒤 행이 나간다', () async {
      final s = await twoRows();
      for (var i = 0; i < OfflineQueueRepositoryImpl.maxAttempts - 1; i++) {
        await s.repository.replayPending();
      }

      final result = await s.repository.replayPending();

      expect(result.failedPermanently, 1);
      expect(result.succeeded, 1);
      expect(result.stillPending, 0);
      final rest = await s.repository.fetchPending();
      expect(rest, hasLength(1));
      expect(rest.single.endpoint, _poisonPath);
      expect(rest.single.failed, isTrue, reason: '사용자가 큐 화면에서 볼 수 있게 남긴다');
      await s.database.close();
    });

    test('영구 실패 행은 다시 재생하지 않고 새 요청의 재생도 막지 않는다', () async {
      final s = await twoRows();
      for (var i = 0; i < OfflineQueueRepositoryImpl.maxAttempts; i++) {
        await s.repository.replayPending();
      }
      s.adapter.paths.clear();

      final replay = await s.repository.replayPending();
      var sent = false;
      final outcome = await s.repository.sendOrQueue<void>(
        endpoint: _healthyPath,
        method: 'PATCH',
        payload: const {'client_key': 'NEW', 'status': 'alighted'},
        send: () async => sent = true,
      );

      expect(s.adapter.paths, isEmpty, reason: '영구 실패 행은 서버로 나가지 않는다');
      expect(replay.stillPending, 0);
      expect(outcome, isA<Sent<void>>());
      expect(sent, isTrue);
      await s.database.close();
    });

    test('나이 상한(30분)을 넘은 행은 5xx 를 한 번만 받아도 영구 실패로 뺀다', () async {
      final s = await twoRows();
      s.clock.current = s.clock.current.add(
        OfflineQueueRepositoryImpl.maxAge + const Duration(minutes: 1),
      );

      final result = await s.repository.replayPending();

      expect(result.failedPermanently, 1);
      expect(result.succeeded, 1);
      await s.database.close();
    });

    test('통신 두절만 이어진 행은 아무리 오래·여러 번 재생해도 영구 실패가 되지 않는다', () async {
      final s = _setup((_) => null);
      await _press(s.repository, _poisonPath, const Failure.network());
      s.clock.current = s.clock.current.add(const Duration(hours: 3));

      for (var i = 0; i < OfflineQueueRepositoryImpl.maxAttempts * 2; i++) {
        final result = await s.repository.replayPending();
        expect(result.stillPending, 1);
        expect(result.failedPermanently, 0);
      }

      expect((await s.repository.fetchPending()).single.failed, isFalse);
      await s.database.close();
    });

    test('새 요청이 들어올 때마다 하는 재생은 시도 횟수에 넣지 않는다', () async {
      // 정류장에서 학생 10명을 연달아 누르는 동안 서버가 죽어 있으면, 누를 때마다 도는 재생이 머리 행을 곧바로
      // 영구 실패로 만들어 버린다 — 시도 횟수는 주기 재생·수동 재시도만 센다.
      final s = _setup((_) => 500);
      await _press(s.repository, _poisonPath, _api(500));

      for (var i = 0; i < OfflineQueueRepositoryImpl.maxAttempts * 2; i++) {
        await _press(s.repository, '/runs/1/riders/${100 + i}', _api(500));
      }

      expect((await s.repository.fetchPending()).first.failed, isFalse);
      await s.database.close();
    });

    test('영구 실패한 행과 같은 처리를 다시 누르면 새로 큐에 쌓인다', () async {
      final s = await twoRows();
      for (var i = 0; i < OfflineQueueRepositoryImpl.maxAttempts; i++) {
        await s.repository.replayPending();
      }

      final outcome = await _press(
        s.repository,
        _poisonPath,
        _api(500),
        payload: {'client_key': 'AGAIN', 'status': 'boarded'},
      );

      expect(outcome, isA<Queued<void>>());
      expect(await s.repository.fetchPending(), hasLength(2));
      await s.database.close();
    });
  });

  // Ruling 616 — 비상 신고는 영구 실패 상한에서 뺀다. 5분 넘는 서버 장애에 신고가 재생에서 조용히 빠지면 아무에게도 안 간
  // 신고가 사라진 것과 같다. `client_key` 가 서버 중복을 막으므로 늦게 도착해도 중복 접수는 없다. 사용자가 큐 화면에서
  // 지울 때까지(또는 성공할 때까지) 재시도한다. 승하차 상한은 위 그룹이 그대로 지킨다.
  group('재생 — 비상 신고는 영구 실패로 빼지 않는다 (Ruling 616)', () {
    const emergencyPath = '/runs/1/emergency';

    Future<void> pressEmergency(OfflineQueueRepositoryImpl repository) =>
        _press(
          repository,
          emergencyPath,
          const Failure.network(),
          method: 'POST',
          payload: {'client_key': 'K-E', 'type': 'accident'},
        );

    test('5xx 가 시도 상한(10회)을 훌쩍 넘어도 영구 실패가 되지 않고 계속 재생 대상이다', () async {
      final s = _setup((_) => 500);
      await pressEmergency(s.repository);

      for (var i = 0; i < OfflineQueueRepositoryImpl.maxAttempts * 3; i++) {
        final result = await s.repository.replayPending();
        expect(result.failedPermanently, 0);
        expect(result.stillPending, 1);
      }

      expect((await s.repository.fetchPending()).single.failed, isFalse);
      await s.database.close();
    });

    test('나이 상한(30분)을 훌쩍 넘어도 5xx 를 받아도 영구 실패가 되지 않는다', () async {
      final s = _setup((_) => 500);
      await pressEmergency(s.repository);
      s.clock.current = s.clock.current.add(const Duration(hours: 3));

      final result = await s.repository.replayPending();

      expect(result.failedPermanently, 0);
      expect(result.stillPending, 1);
      expect((await s.repository.fetchPending()).single.failed, isFalse);
      await s.database.close();
    });

    test('서버가 한참 뒤 돌아오면 그 신고가 나가고 큐가 빈다', () async {
      var serverUp = false;
      final s = _setup((_) => serverUp ? 201 : 500);
      await pressEmergency(s.repository);
      for (var i = 0; i < OfflineQueueRepositoryImpl.maxAttempts * 2; i++) {
        await s.repository.replayPending();
      }

      serverUp = true;
      final result = await s.repository.replayPending();

      expect(result.succeeded, 1);
      expect(await s.repository.fetchPending(), isEmpty);
      await s.database.close();
    });

    test('큐 머리의 비상 신고가 계속 5xx 여도 뒤 승하차 행을 막지 않는다', () async {
      // 비상이 막히면 승하차가 영구히 못 나간다 — 상한을 없앤 대신 뒤 행을 건너뛰어 이어 보낸다.
      final s = _setup((path) => path == emergencyPath ? 500 : 200);
      await pressEmergency(s.repository);
      await _press(s.repository, _healthyPath, const Failure.network());

      final result = await s.repository.replayPending();

      expect(result.succeeded, 1, reason: '뒤 승하차 행은 나간다');
      expect(result.stillPending, 1, reason: '비상 신고는 남는다');
      final rest = await s.repository.fetchPending();
      expect(rest.single.endpoint, emergencyPath);
      await s.database.close();
    });
  });

  // S-9 ③ — 재생 순서는 id(쌓인 순서)로 명시한다. 일반 SELECT 는 구현 세부(rowid 순)에 기대고 있었다.
  test('재생과 대기 목록은 id 오름차순이다', () async {
    final s = _setup((_) => 200);
    for (final id in [5, 2, 9]) {
      await s.database
          .into(s.database.pendingRequests)
          .insert(
            PendingRequestsCompanion.insert(
              id: Value(id),
              endpoint: '/runs/1/riders/$id',
              method: const Value('PATCH'),
              payload: '{"status":"boarded"}',
            ),
          );
    }

    expect((await s.repository.fetchPending()).map((e) => e.id), [2, 5, 9]);
    await s.repository.replayPending();

    expect(s.adapter.paths, [
      '/runs/1/riders/2',
      '/runs/1/riders/5',
      '/runs/1/riders/9',
    ]);
    await s.database.close();
  });
}
