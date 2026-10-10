import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:manager_app/features/offline_queue/domain/offline_queue_repository.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/roster/data/roster_api.dart';

import '../../support/fake_roster_key_store.dart';
import '../../support/fake_token_storage.dart';

const Map<String, dynamic> _rosterJson = {
  'run_id': 'run-A',
  'bus_no': '3호차',
  'direction': 'to_academy',
  'counts': {'boarded': 0, 'waiting': 1, 'no_show': 0, 'absent_n': 0},
  'stops': [
    {
      'stop_id': 's1',
      'seq': 1,
      'name': 'A정류장',
      'students': [
        {
          'rider_id': 'r1',
          'student_id': 'st1',
          'name': '김바래',
          'photo_url': null,
          'class_name': '초3',
          'guardian_phone': '010-****-1234',
          'note': '견과류 알레르기',
          'can_go_alone': true,
          'status': 'waiting',
        },
      ],
    },
  ],
};

/// 대기열 정리가 실패하는 상황 — 기기 저장소 오류.
class _BrokenQueue implements OfflineQueueRepository {
  @override
  Future<List<PendingRequestSummary>> fetchPending() async =>
      throw StateError('테스트 — 대기열 읽기 실패');

  @override
  Future<void> clear() async => throw StateError('테스트 — 대기열 삭제 실패');

  @override
  Future<SendOutcome<T>> sendOrQueue<T>({
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
    required Future<T> Function() send,
  }) async => throw UnimplementedError();

  @override
  Future<ReplayResult> replayPending() async => throw UnimplementedError();

  @override
  Future<void> cancel(int id) async => throw UnimplementedError();
}

/// 재발급 요청에 `401` 을 돌려주는 어댑터 — refresh 토큰이 거절된 상황.
class _RejectRefreshAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{"error":{"code":"TOKEN_EXPIRED","message":"m"}}',
    401,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

/// 응답을 [gate] 가 풀어 줄 때까지 붙들어 두는 어댑터 — 요청을 보낸 뒤 로그아웃하는 순서를 만든다.
class _GatedRosterAdapter implements HttpClientAdapter {
  final gate = Completer<void>();

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await gate.future;
    return ResponseBody.fromString(
      jsonEncode(_rosterJson),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

/// M-2 — 기기에 남긴 개인정보(명단 · 특이사항)는 로그아웃·세션 만료에 **빠짐없이 먼저** 지운다.
void main() {
  late OfflineQueueDatabase database;
  late ProviderContainer container;

  setUp(() {
    database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  ProviderContainer buildContainer({
    List<Override> extra = const [],
    HttpClientAdapter? refreshAdapter,
  }) {
    final tokens = FakeTokenStorage(
      seedRefreshToken: 'r',
      seedAccessToken: 'a',
    );
    return container = ProviderContainer(
      overrides: [
        tokenStorageProvider.overrideWithValue(tokens),
        offlineQueueDatabaseProvider.overrideWithValue(database),
        rosterKeyStoreProvider.overrideWithValue(FakeRosterKeyStore()),
        apiClientProvider.overrideWith(
          (ref) => ApiClient(
            tokenStorage: tokens,
            baseUrl: 'https://example.invalid',
            refreshDio: Dio(BaseOptions(baseUrl: 'https://example.invalid'))
              ..httpClientAdapter = refreshAdapter ?? _RejectRefreshAdapter(),
          ),
        ),
        ...extra,
      ],
    );
  }

  // 정리가 끝날 때까지 이벤트 루프를 돌린다 — 정리는 알림 안에서 기다리지 않고 시작한다.
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('대기열 정리가 예외를 던져도 기기에 저장한 명단은 지워진다', () async {
    buildContainer(
      extra: [offlineQueueRepositoryProvider.overrideWithValue(_BrokenQueue())],
    );
    container.read(routerRefreshNotifierProvider);
    container.read(currentUserRoleProvider.notifier).state = UserRole.driver;
    await container.read(rosterCacheProvider).save('run-A', _rosterJson);
    expect(await container.read(rosterCacheProvider).read('run-A'), isNotNull);

    // 대기열 정리의 예외는 알림 밖으로 새어 나가는 비동기 오류다 — 시험이 이 오류로 죽지 않게 구역을 따로 둔다.
    final uncaught = <Object>[];
    final done = Completer<void>();
    unawaited(
      runZonedGuarded(() async {
        container.read(currentUserRoleProvider.notifier).state = null;
        await settle();
        done.complete();
      }, (error, _) => uncaught.add(error)),
    );
    await done.future;

    expect(
      await container.read(rosterCacheProvider).read('run-A'),
      isNull,
      reason: '명단(특이사항 포함)은 대기열보다 먼저 지운다',
    );
  });

  // 앱을 켜 세션을 되살리다 refresh 토큰이 거절되면 역할이 처음부터 비어 있어 "역할이 비는 순간" 정리가 돌지 않는다.
  test('앱을 켤 때 세션 복구가 거절돼도(역할이 원래 비어 있어도) 저장한 명단·대기열을 비운다', () async {
    buildContainer();
    container.read(routerRefreshNotifierProvider);
    await container.read(rosterCacheProvider).save('run-A', _rosterJson);
    await container
        .read(offlineQueueRepositoryProvider)
        .sendOrQueue<void>(
          endpoint: '/runs/run-A/riders/7',
          method: 'PATCH',
          payload: const {'client_key': 'K', 'status': 'boarded'},
          // Failure 는 Exception/Error 를 상속하지 않는다.
          // ignore: only_throw_errors
          send: () => throw const Failure.network(),
        );
    expect(container.read(currentUserRoleProvider), isNull);

    await container.read(apiClientProvider).tokenRefresher.refresh();
    await settle();

    expect(await container.read(rosterCacheProvider).read('run-A'), isNull);
    expect(
      await container.read(offlineQueueRepositoryProvider).fetchPending(),
      isEmpty,
    );
  });

  test('로그아웃 뒤에 늦게 도착한 명단 응답은 기기에 다시 저장하지 않는다', () async {
    final adapter = _GatedRosterAdapter();
    buildContainer(
      extra: [
        rosterApiProvider.overrideWithValue(
          RosterApi(
            dio: Dio(BaseOptions(baseUrl: 'https://example.invalid'))
              ..httpClientAdapter = adapter,
          ),
        ),
      ],
    );
    container.read(currentUserRoleProvider.notifier).state = UserRole.driver;

    final pending = container
        .read(rosterRepositoryProvider)
        .fetchRoster('run-A');
    container.read(currentUserRoleProvider.notifier).state = null;
    adapter.gate.complete();
    await pending;
    await settle();

    expect(await container.read(rosterCacheProvider).read('run-A'), isNull);
  });

  test('로그인한 채 받은 명단은 기기에 저장한다(대조)', () async {
    final adapter = _GatedRosterAdapter()..gate.complete();
    buildContainer(
      extra: [
        rosterApiProvider.overrideWithValue(
          RosterApi(
            dio: Dio(BaseOptions(baseUrl: 'https://example.invalid'))
              ..httpClientAdapter = adapter,
          ),
        ),
      ],
    );
    container.read(currentUserRoleProvider.notifier).state = UserRole.driver;

    await container.read(rosterRepositoryProvider).fetchRoster('run-A');

    expect(await container.read(rosterCacheProvider).read('run-A'), isNotNull);
  });
}
