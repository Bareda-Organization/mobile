import 'dart:typed_data';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/domain/manager_run_repository.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:manager_app/features/position/presentation/position_transmitter.dart';

import '../../support/fake_token_storage.dart';

class _CountingRunsRepository implements ManagerRunRepository {
  int fetches = 0;

  @override
  Future<List<ManagerRun>> fetchRuns({DateTime? date}) async {
    fetches++;
    return const [];
  }
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

/// F06-02 — 로그아웃·세션 만료로 역할이 비면 이 계정 소유의 상태(오프라인 큐·회차 캐시·선택값)를
/// 함께 비운다. 다음 계정이 이전 계정의 대기 요청을 자기 토큰으로 재생하거나 이전 목록을 보면 안 된다.
/// K-02① — REST 재발급 실패(`ApiClient.sessionExpired`)도 같은 경로로 역할을 비운다.
void main() {
  late OfflineQueueDatabase database;
  late _CountingRunsRepository runs;
  late ProviderContainer container;

  setUp(() {
    database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
    runs = _CountingRunsRepository();
    final tokens = FakeTokenStorage(
      seedRefreshToken: 'r',
      seedAccessToken: 'a',
    );
    container = ProviderContainer(
      overrides: [
        tokenStorageProvider.overrideWithValue(tokens),
        offlineQueueDatabaseProvider.overrideWithValue(database),
        managerRunRepositoryProvider.overrideWithValue(runs),
        apiClientProvider.overrideWith(
          (ref) => ApiClient(
            tokenStorage: tokens,
            baseUrl: 'https://example.invalid',
            refreshDio: Dio(BaseOptions(baseUrl: 'https://example.invalid'))
              ..httpClientAdapter = _RejectRefreshAdapter(),
          ),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });
    container.read(routerRefreshNotifierProvider);
  });

  Future<void> loginWithLeftovers() async {
    container.read(currentUserRoleProvider.notifier).state = UserRole.escort;
    container.read(selectedRunIdProvider.notifier).state = 'run-A';
    container.read(transmissionEndedRunIdProvider.notifier).state = 'run-A';
    await container.read(todayRunsProvider.future);
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
    expect(
      await container.read(offlineQueueRepositoryProvider).fetchPending(),
      hasLength(1),
    );
  }

  Future<void> expectCleared() async {
    // 큐 비우기는 비동기 — 이벤트 루프를 한 바퀴 돌린다.
    await Future<void>.delayed(Duration.zero);
    expect(container.read(selectedRunIdProvider), isNull);
    expect(container.read(transmissionEndedRunIdProvider), isNull);
    expect(
      await container.read(offlineQueueRepositoryProvider).fetchPending(),
      isEmpty,
    );
    await container.read(todayRunsProvider.future);
    expect(runs.fetches, 2, reason: '이전 계정의 회차 목록 캐시를 버리고 다시 받는다');
  }

  test('역할이 비면(로그아웃) 대기 큐·선택값·회차 캐시를 비운다', () async {
    await loginWithLeftovers();

    container.read(currentUserRoleProvider.notifier).state = null;

    await expectCleared();
  });

  test(
    'REST 재발급이 401 로 거절되면(ApiClient.sessionExpired) 역할을 비우고 같이 정리한다',
    () async {
      await loginWithLeftovers();

      final result = await container
          .read(apiClientProvider)
          .tokenRefresher
          .refresh();
      expect(result, isNull);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(currentUserRoleProvider), isNull);
      await expectCleared();
    },
  );
  // L7(Ruling 388 · 616) — 세션이 만료돼 큐를 비울 때 보내지 못한 처리를 안내 없이 지우지 않는다. 비상 신고가 섞여
  // 있으면 그것을 따로 밝힌다. 직접 로그아웃은 확인 창이 이미 알려 주므로 만료 안내를 만들지 않는다.
  test('세션 만료로 큐를 비울 때 버려지는 처리 건수를 만료 안내에 밝힌다', () async {
    await loginWithLeftovers();
    await container
        .read(offlineQueueRepositoryProvider)
        .sendOrQueue<void>(
          endpoint: '/runs/run-A/emergency',
          method: 'POST',
          payload: const {'client_key': 'E', 'type': 'etc'},
          // Failure 는 Exception/Error 를 상속하지 않는다.
          // ignore: only_throw_errors
          send: () => throw const Failure.network(),
        );

    await container.read(apiClientProvider).tokenRefresher.refresh();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final notice = container.read(sessionExpiredNoticeProvider);
    expect(notice, contains('로그인이 만료됐습니다'));
    expect(notice, contains('보내지 못한 처리 2건'));
    expect(notice, contains('비상 신고 1건'));
  });

  test('직접 로그아웃은 만료 안내를 만들지 않는다', () async {
    await loginWithLeftovers();

    container.read(currentUserRoleProvider.notifier).state = null;
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(sessionExpiredNoticeProvider), isNull);
  });
}
