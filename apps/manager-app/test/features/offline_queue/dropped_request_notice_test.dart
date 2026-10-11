import 'dart:typed_data';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/launcher/device_launchers.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_repository_impl.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_auto_sync.dart';
import 'package:manager_app/features/offline_queue/presentation/request_notices.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';

/// 모든 요청에 [status] 와 에러 본문으로 답한다 — 서버의 확정 거절.
class _RejectAdapter implements HttpClientAdapter {
  new(this.status, {this.code = 'RIDER_TRANSITION_NOT_ALLOWED'});

  final int status;
  final String code;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{"error":{"code":"$code","message":"서버 문구"}}',
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

const _boarded = {'client_key': 'K', 'status': 'boarded'};

/// Ruling 882 — 큐 재생이 서버의 확정 거절로 행을 지울 때는 반드시 안내를 남긴다. 30초 자동 재생 · 쓰기 직전 재생 ·
/// 수동
/// 재시도 어느 경로로 지워져도 사용자가 확인할 때까지 화면에 남고, 비상 신고면 "전송되지 않았습니다" 와 학원 전화를 띄운다.
void main() {
  late OfflineQueueDatabase database;
  late List<List<DroppedRequest>> dropped;

  setUp(() {
    database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
    dropped = [];
  });
  tearDown(() => database.close());

  OfflineQueueRepositoryImpl repo(int status) => OfflineQueueRepositoryImpl(
    database: database,
    dio: Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = _RejectAdapter(status),
    onDropped: dropped.add,
  );

  Future<void> queue(
    OfflineQueueRepositoryImpl repository,
    String endpoint, {
    String method = 'PATCH',
    Map<String, dynamic> payload = _boarded,
  }) => repository.sendOrQueue<void>(
    endpoint: endpoint,
    method: method,
    payload: payload,
    // Failure 는 Exception/Error 를 상속하지 않는다.
    // ignore: only_throw_errors
    send: () => throw const Failure.network(),
  );

  group('저장소', () {
    test('수동 재시도가 확정 거절로 지운 행의 내용(요청 · 상태 · 서버 문구)이 결과와 콜백으로 나온다', () async {
      final repository = repo(409);
      await queue(repository, '/runs/run-A/riders/7');

      final result = await repository.replayPending();

      expect(result.droppedPermanently, 1);
      final item = result.dropped.single;
      expect(item.request.endpoint, '/runs/run-A/riders/7');
      expect(item.request.description, '탑승 처리');
      expect(item.statusCode, 409);
      expect(item.code, 'RIDER_TRANSITION_NOT_ALLOWED');
      expect(item.message, '서버 문구');
      expect(dropped.single.single.request.endpoint, '/runs/run-A/riders/7');
    });

    test('다음 쓰기 직전 재생이 지운 행도 콜백으로 알린다(결과를 버리는 경로)', () async {
      final repository = repo(403);
      await queue(repository, '/runs/run-A/riders/7');

      // 새 요청 앞의 재생이 앞 행을 확정 거절로 지운다 — 호출부는 그 결과를 받지 않는다.
      await repository.sendOrQueue<void>(
        endpoint: '/runs/run-A/riders/8',
        method: 'PATCH',
        payload: const {'client_key': 'K2', 'status': 'boarded'},
        send: () async {},
      );

      expect(dropped, hasLength(1));
      expect(dropped.single.single.request.endpoint, '/runs/run-A/riders/7');
    });

    test('서버가 5xx 로 답해 남겨 둔 행은 지운 것이 아니므로 알리지 않는다', () async {
      final repository = repo(503);
      await queue(repository, '/runs/run-A/riders/7');

      await repository.replayPending();

      expect(dropped, isEmpty);
    });
  });

  group('안내 띠', () {
    Future<ProviderContainer> pumpHost(
      WidgetTester tester, {
      List<Uri>? opened,
      String? contact,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            academyContactProvider.overrideWith((ref) => contact),
            rosterProvider.overrideWith(
              (ref) async => const RosterResponse(
                runId: 'run-A',
                busNo: '1호차',
                direction: RunDirection.toAcademy,
                counts: RosterCounts(
                  boarded: 0,
                  waiting: 1,
                  noShow: 0,
                  absentN: 0,
                ),
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
                        status: RiderStatus.waiting,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (opened != null)
              uriOpenerProvider.overrideWithValue((uri) async {
                opened.add(uri);
                return true;
              }),
          ],
          child: MaterialApp(
            builder: (context, child) => RequestNoticesHost(child: child!),
            home: const Scaffold(body: Text('본 화면')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.text('본 화면')));
    }

    DroppedRequest rider() => DroppedRequest(
      request: PendingRequestSummary(
        id: 1,
        endpoint: '/runs/run-A/riders/7',
        method: 'PATCH',
        payload: '{"status":"boarded"}',
        createdAt: DateTime(2026, 10, 11),
      ),
      statusCode: 409,
      code: 'RIDER_TRANSITION_NOT_ALLOWED',
      message: '서버 문구',
    );

    DroppedRequest emergency() => DroppedRequest(
      request: PendingRequestSummary(
        id: 2,
        endpoint: '/runs/run-A/emergency',
        method: 'POST',
        payload: '{"type":"accident"}',
        createdAt: DateTime(2026, 10, 11),
      ),
      statusCode: 403,
      code: 'FORBIDDEN',
      message: '서버 문구',
    );

    testWidgets('승하차 행이 지워지면 학생 · 처리 · 이유가 확인할 때까지 남는다', (tester) async {
      final container = await pumpHost(tester);
      await container.read(rosterProvider.future);
      expect(find.textContaining('서버로 보내지 못하고'), findsNothing);

      container.read(requestNoticesProvider.notifier).addDropped([rider()]);
      await tester.pumpAndSettle();

      expect(find.textContaining('탑승 처리 · 김하늘'), findsOneWidget);
      expect(find.textContaining('이미 처리된 학생입니다'), findsOneWidget);
      // 시간이 지나도 사라지지 않는다.
      await tester.pump(const Duration(minutes: 5));
      expect(find.textContaining('탑승 처리 · 김하늘'), findsOneWidget);

      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(find.textContaining('탑승 처리 · 김하늘'), findsNothing);
    });

    testWidgets('비상 신고 행이 지워지면 전송되지 않았다는 안내와 학원 전화 단추가 뜬다', (tester) async {
      final opened = <Uri>[];
      final container = await pumpHost(
        tester,
        opened: opened,
        contact: '032-000-1100',
      );

      container.read(requestNoticesProvider.notifier).addDropped([emergency()]);
      await tester.pumpAndSettle();

      expect(find.text('비상 신고가 전송되지 않았습니다'), findsOneWidget);
      await tester.tap(find.text('전화'));
      await tester.pump();
      expect(opened.single, Uri(scheme: 'tel', path: '032-000-1100'));
    });

    testWidgets('안내가 뜨고 지워져도 아래 화면의 입력 내용이 사라지지 않는다', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            builder: (context, child) => RequestNoticesHost(child: child!),
            home: const Scaffold(body: TextField()),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '작성 중');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TextField)),
      );

      container.read(requestNoticesProvider.notifier).addDropped([rider()]);
      await tester.pumpAndSettle();
      expect(find.text('작성 중'), findsOneWidget);

      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(find.text('작성 중'), findsOneWidget);
    });

    testWidgets('30초 자동 재생이 확정 거절로 지우면 안내가 앱 맨 위에 뜬다', (tester) async {
      final repository = repo(403);
      await queue(repository, '/runs/run-A/emergency', method: 'POST');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            offlineQueueRepositoryProvider.overrideWith(
              (ref) => OfflineQueueRepositoryImpl(
                database: database,
                dio: Dio(BaseOptions(baseUrl: 'https://example.invalid'))
                  ..httpClientAdapter = _RejectAdapter(403, code: 'FORBIDDEN'),
                onDropped: (dropped) => ref
                    .read(requestNoticesProvider.notifier)
                    .addDropped(dropped),
              ),
            ),
            currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
          ],
          child: MaterialApp(
            builder: (context, child) => RequestNoticesHost(child: child!),
            home: const OfflineQueueAutoSync(child: Text('본 화면')),
          ),
        ),
      );
      expect(find.text('비상 신고가 전송되지 않았습니다'), findsNothing);

      await tester.runAsync(() async {
        await tester.pump(OfflineQueueAutoSync.interval);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(find.text('비상 신고가 전송되지 않았습니다'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
