import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_repository_impl.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/offline_queue/presentation/request_notices.dart';
import 'package:manager_app/features/roster/data/models/no_show_contact_request.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/data/roster_api.dart';
import 'package:manager_app/features/roster/data/roster_repository_impl.dart';
import 'package:manager_app/features/roster/domain/roster_cache.dart';
import 'package:manager_app/features/roster/presentation/roster_actions.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/run_end/data/models/report_request.dart';
import 'package:manager_app/features/run_end/data/reports_api.dart';
import 'package:manager_app/features/run_end/data/reports_repository_impl.dart';

/// 서버 대역 — `offline` 이면 연결이 끊기고, 아니면 정해진 상태로 답하고, 나간 요청의 본문을 기록한다.
class _Server implements HttpClientAdapter {
  /// 참이면 연결 실패, 아니면 `status` · `body` 로 답한다.
  bool offline = true;
  int status = 201;
  String body = '{"report_id":"9","reported_at":"2026-10-13T09:00:00+09:00"}';
  String contentType = Headers.jsonContentType;

  final List<Map<String, dynamic>> sentBodies = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = options.data;
    if (data is Map<String, dynamic>) sentBodies.add(data);
    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }
}

class _NoCache implements RosterCache {
  @override
  Future<void> save(String runId, Map<String, dynamic> json) async {}

  @override
  Future<({Map<String, dynamic> json, DateTime savedAt})?> read(
    String runId,
  ) async => null;

  @override
  Future<void> clear() async {}
}

const _roster = RosterResponse(
  runId: 'run-A',
  busNo: '1호차',
  direction: RunDirection.toAcademy,
  counts: RosterCounts(boarded: 0, waiting: 0, noShow: 1, absentN: 0),
  stops: [
    RosterStop(
      stopId: 's1',
      seq: 1,
      name: '정류장',
      students: [
        RosterStudent(
          riderId: '7',
          studentId: 'st7',
          name: '김하늘',
          photoUrl: null,
          guardianPhone: null,
          canGoAlone: false,
          status: RiderStatus.noShow,
        ),
      ],
    ),
  ],
);

const _rejection = '{"error":{"code":"VALIDATION_FAILED","message":"서버 문구"}}';

/// R56 · Ruling 894 ⑧ — 예외 보고와 미승차 연락 기록은 통신 두절 때 승하차와 같은 대기열에 쌓이고,
/// 같은 재생 · 같은 거절 안내 규칙을 따른다. 요청마다 한 번 만든 `client_key` 를 재전송에 그대로 쓴다(§1.7).
void main() {
  late OfflineQueueDatabase database;
  late _Server server;
  late Dio dio;
  late List<List<DroppedRequest>> dropped;
  late OfflineQueueRepositoryImpl queue;

  setUp(() {
    database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
    server = _Server();
    dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = server;
    dropped = [];
    queue = OfflineQueueRepositoryImpl(
      database: database,
      dio: dio,
      onDropped: dropped.add,
    );
  });
  tearDown(() => database.close());

  ReportRequest report({String key = 'K-REPORT'}) => ReportRequest(
    type: ReportType.guardianAbsent,
    memo: '보호자가 안 나왔어요',
    clientKey: key,
    riderId: '7',
  );

  Future<SendOutcome<Object?>> submitReport(ReportRequest request) =>
      ReportsRepositoryImpl(
        api: ReportsApi(dio: dio),
        offlineQueue: queue,
      ).submitReport(runId: 'run-A', request: request);

  group('예외 보고', () {
    test('통신이 끊기면 대기열 행이 되고, 복구 뒤 재생은 같은 client_key 로 한 번 나간다', () async {
      final outcome = await submitReport(report());

      expect(outcome, isA<Queued<Object?>>());
      final row = (await queue.fetchPending()).single;
      expect(row.endpoint, '/runs/run-A/reports');
      expect(row.method, 'POST');
      expect(jsonDecode(row.payload), containsPair('client_key', 'K-REPORT'));
      expect(row.description, '보호자 부재 보고');

      server.offline = false;
      final result = await queue.replayPending();

      expect(result.succeeded, 1);
      expect(await queue.fetchPending(), isEmpty);
      // 처음 시도(끊김) + 재생 1회 — 둘 다 같은 키다.
      expect(server.sentBodies.map((b) => b['client_key']), [
        'K-REPORT',
        'K-REPORT',
      ]);
    });

    test('서버가 받으면 바로 접수되고 큐에는 아무것도 남지 않는다', () async {
      server.offline = false;

      final outcome = await submitReport(report());

      expect(outcome, isA<Sent<Object?>>());
      expect(await queue.fetchPending(), isEmpty);
    });

    test('재생 중 JSON 4xx 거절은 행을 지우고 지운 내용을 안내로 올린다', () async {
      await submitReport(report());
      server
        ..offline = false
        ..status = 422
        ..body = _rejection;

      final result = await queue.replayPending();

      expect(result.droppedPermanently, 1);
      expect(await queue.fetchPending(), isEmpty);
      expect(dropped.single.single.request.description, '보호자 부재 보고');
      expect(dropped.single.single.code, 'VALIDATION_FAILED');
    });

    for (final (label, status, body, type) in <(String, int, String, String)>[
      ('5xx', 503, _rejection, Headers.jsonContentType),
      ('게이트웨이 HTML 4xx', 400, '<html>bad</html>', Headers.textPlainContentType),
      ('빈 본문 4xx', 400, '', Headers.jsonContentType),
    ]) {
      test('재생 중 $label 는 행을 남기고 안내하지 않는다', () async {
        await submitReport(report());
        server
          ..offline = false
          ..status = status
          ..body = body
          ..contentType = type;

        await queue.replayPending();

        expect(await queue.fetchPending(), hasLength(1));
        expect(dropped, isEmpty);
      });
    }
  });

  group('미승차 연락 기록', () {
    var rosterFetches = 0;

    ProviderContainer open() {
      rosterFetches = 0;
      final container = ProviderContainer(
        overrides: [
          rosterProvider.overrideWith((ref) async {
            rosterFetches++;
            return _roster;
          }),
          offlineQueueRepositoryProvider.overrideWithValue(queue),
          rosterRepositoryProvider.overrideWithValue(
            RosterRepositoryImpl(
              api: RosterApi(dio: dio),
              offlineQueue: queue,
              cache: _NoCache(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    NoShowContactRequest contact({String key = 'K-CONTACT'}) =>
        NoShowContactRequest(
          attemptType: NoShowAttemptType.call,
          result: NoShowContactResult.noAnswer,
          clientKey: key,
        );

    test('통신이 끊기면 대기열 행이 되고 명단은 다시 받지 않으며, 복구 뒤 재생은 같은 키로 한 번 나간다', () async {
      // 명단을 구독해 두어, 연락 기록 뒤 무효화되면 다시 받아지는지 센다.
      final container = open()..listen(rosterProvider, (_, _) {});
      await container.read(rosterProvider.future);

      final outcome = await submitNoShowContact(
        container,
        runId: 'run-A',
        riderId: '7',
        request: contact(),
      );

      await pumpEventQueue();
      expect(outcome.error, isNull);
      expect(outcome.queued, isTrue);
      expect(rosterFetches, 1, reason: '서버에 반영되지 않았으니 명단을 다시 받지 않는다');
      final row = (await queue.fetchPending()).single;
      expect(row.endpoint, '/runs/run-A/riders/7/no-show-contacts');
      expect(row.method, 'POST');
      expect(row.description, '미승차 연락 기록');
      // 연락 기록은 상태 처리가 아니라 명단 행을 "전송 대기" 로 바꾸지 않는다.
      expect(row.riderId, isNull);
      expect(jsonDecode(row.payload), containsPair('client_key', 'K-CONTACT'));

      server
        ..offline = false
        ..status = 201
        ..body = '{}';
      final result = await queue.replayPending();

      expect(result.succeeded, 1);
      expect(server.sentBodies.map((b) => b['client_key']), [
        'K-CONTACT',
        'K-CONTACT',
      ]);
    });

    test('서버가 받으면 queued 가 아니다', () async {
      server
        ..offline = false
        ..body = '{}';

      final container = open()..listen(rosterProvider, (_, _) {});
      await container.read(rosterProvider.future);

      final outcome = await submitNoShowContact(
        container,
        runId: 'run-A',
        riderId: '7',
        request: contact(),
      );

      await pumpEventQueue();
      expect(outcome.error, isNull);
      expect(outcome.queued, isFalse);
      expect(rosterFetches, 2, reason: '서버가 받았으니 명단을 다시 받는다');
      expect(await queue.fetchPending(), isEmpty);
    });

    test('재생 중 JSON 4xx 거절은 행을 지우고 안내로 올린다', () async {
      await submitNoShowContact(
        open(),
        runId: 'run-A',
        riderId: '7',
        request: contact(),
      );
      server
        ..offline = false
        ..status = 404
        ..body = '{"error":{"code":"NO_SHOW_CASE_NOT_FOUND","message":"m"}}';

      final result = await queue.replayPending();

      expect(result.droppedPermanently, 1);
      expect(await queue.fetchPending(), isEmpty);
      expect(dropped.single.single.request.description, '미승차 연락 기록');
    });

    test('5xx 는 행을 남긴다', () async {
      await submitNoShowContact(
        open(),
        runId: 'run-A',
        riderId: '7',
        request: contact(),
      );
      server
        ..offline = false
        ..status = 503
        ..body = _rejection;

      await queue.replayPending();

      expect(await queue.fetchPending(), hasLength(1));
      expect(dropped, isEmpty);
    });

    test('안내에는 명단에서 찾은 학생 이름이 붙는다(메모리 안내만 · 기기 저장은 이름 없음)', () {
      final request = PendingRequestSummary(
        id: 1,
        endpoint: '/runs/run-A/riders/7/no-show-contacts',
        method: 'POST',
        payload: '{}',
        createdAt: DateTime(2026, 10, 13),
      );

      expect(rosterNameOf(_roster, request), '김하늘');
    });
  });
}
