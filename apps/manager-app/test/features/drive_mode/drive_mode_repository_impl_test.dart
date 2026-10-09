import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/drive_mode/data/drive_mode_api.dart';
import 'package:manager_app/features/drive_mode/data/drive_mode_repository_impl.dart';
import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_repository_impl.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';

/// 가로챈 요청을 기록하고 [respond] 가 정한 응답을 돌려주는 가짜 어댑터 — 소켓을 열지 않는다.
class _FakeAdapter implements HttpClientAdapter {
  new(this.respond);

  final Future<ResponseBody> Function(RequestOptions options) respond;
  final List<RequestOptions> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return respond(options);
  }
}

/// API_SPEC §4.5 의 정상 응답(마지막 지점이 아닌 도착).
const _arriveBody =
    '{"arrived_at":"2026-10-10T08:00:00Z","next_stop":{"stop_id":"21",'
    '"stop_name":"다음 승하차지"},"is_final":false,"run_status":"moving",'
    '"finish_pending":false,"remaining":[]}';

void main() {
  late OfflineQueueDatabase database;

  setUp(() {
    database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  DriveModeRepositoryImpl buildRepository(_FakeAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = adapter;
    return DriveModeRepositoryImpl(
      api: DriveModeApi(dio: dio),
      offlineQueue: OfflineQueueRepositoryImpl(database: database, dio: dio),
    );
  }

  // 859 — 도착 처리는 오프라인 큐를 거친다. 연결이 안 되면 잃지 않고 쌓고, 재생이 같은 경로로 다시 보내야 한다.
  test(
    'arriveStop: 연결 실패면 큐에 쌓고, 큐 행은 POST /runs/<회차>/stops/<승하차지>/arrive 이다',
    () async {
      final adapter = _FakeAdapter(
        (options) async => throw DioException.connectionError(
          requestOptions: options,
          reason: '테스트 — 통신 두절',
        ),
      );
      final repository = buildRepository(adapter);

      final outcome = await repository.arriveStop(runId: '7', stopId: '21');

      expect(outcome, isA<Queued<ArriveStopResult>>());
      final pending = await OfflineQueueRepositoryImpl(
        database: database,
        dio: Dio(),
      ).fetchPending();
      expect(pending, hasLength(1));
      expect(pending.single.endpoint, '/runs/7/stops/21/arrive');
      expect(pending.single.method, 'POST');
      expect(pending.single.isArrive, isTrue);
      expect(pending.single.arriveStopId, '21');
    },
  );

  test('arriveStop: 2xx 응답이면 전송 완료이고 큐에는 아무것도 쌓이지 않는다', () async {
    final adapter = _FakeAdapter(
      (options) async => ResponseBody.fromString(
        _arriveBody,
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
    final repository = buildRepository(adapter);

    final outcome = await repository.arriveStop(runId: '7', stopId: '21');

    expect(outcome, isA<Sent<ArriveStopResult>>());
    expect((outcome as Sent<ArriveStopResult>).value.nextStop?.stopId, '21');
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path, '/runs/7/stops/21/arrive');
    expect(
      await OfflineQueueRepositoryImpl(
        database: database,
        dio: Dio(),
      ).fetchPending(),
      isEmpty,
    );
  });
}
