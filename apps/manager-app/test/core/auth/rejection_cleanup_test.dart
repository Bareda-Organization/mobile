import 'dart:typed_data';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/academy_contact_store.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/last_session_store.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/home/data/run_summary_store.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';

import '../../support/fake_academy_contact_store.dart';
import '../../support/fake_last_session_store.dart';
import '../../support/fake_roster_key_store.dart';
import '../../support/fake_run_summary_store.dart';
import '../../support/fake_token_storage.dart';
import '../../support/manager_run_fixture.dart';

/// `/me` 가 [failure] 로 실패하는 가짜.
class _FailingMe implements AuthRepository {
  new(this.failure);

  final Failure failure;

  @override
  Future<MeResponse> me() async {
    // Failure 는 Exception/Error 를 상속하지 않는다.
    // ignore: only_throw_errors
    throw failure;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 모든 요청에 `403 AUTH_PENDING` 을 돌려주는 어댑터 — 인터셉터가 게이트 이벤트를 낸다.
class _PendingAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{"error":{"code":"AUTH_PENDING","message":"m"}}',
    403,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

/// R52 최종 대조 — 서버가 계정을 **긍정으로 거절**했다는 증거(부트스트랩 `/me` 403 · 대기·거절 게이트)가 있으면
/// 로그아웃과 같은 범위(명단 저장본 · 암호 키 · 회차 요약 · 저장 역할 · 대기열)를 지운다(NFR-08).
void main() {
  late OfflineQueueDatabase database;
  late FakeRosterKeyStore keyStore;
  late FakeLastSessionStore lastSession;
  late FakeRunSummaryStore summary;
  late FakeTokenStorage tokens;

  setUp(() {
    database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
    keyStore = FakeRosterKeyStore();
    lastSession = FakeLastSessionStore(AccountRole.driver);
    summary = FakeRunSummaryStore((
      savedAt: DateTime(2026, 10, 10, 9),
      runs: [managerRunFixture()],
    ));
    tokens = FakeTokenStorage(seedRefreshToken: 'r', seedAccessToken: 'a');
  });

  tearDown(() => database.close());

  ProviderContainer build({AuthRepository? auth, HttpClientAdapter? adapter}) {
    final container = ProviderContainer(
      overrides: [
        tokenStorageProvider.overrideWithValue(tokens),
        offlineQueueDatabaseProvider.overrideWithValue(database),
        rosterKeyStoreProvider.overrideWithValue(keyStore),
        lastSessionStoreProvider.overrideWithValue(lastSession),
        runSummaryStoreProvider.overrideWithValue(summary),
        academyContactStoreProvider.overrideWithValue(
          FakeAcademyContactStore(),
        ),
        if (auth != null) authRepositoryProvider.overrideWithValue(auth),
        if (adapter != null)
          apiClientProvider.overrideWith(
            (ref) => ApiClient(
              tokenStorage: tokens,
              baseUrl: 'https://example.invalid',
              dio: Dio(BaseOptions(baseUrl: 'https://example.invalid'))
                ..httpClientAdapter = adapter,
            ),
          ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 기기에 명단 저장본(암호 키 포함) 한 건과 대기 요청 한 건을 만들어 둔다.
  Future<void> seedDeviceState(ProviderContainer container) async {
    await container.read(rosterCacheProvider).save('run-A', {
      'run_id': 'run-A',
    });
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
    expect(keyStore.key, isNotNull);
  }

  Future<void> expectEverythingForgotten(ProviderContainer container) async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(await database.select(database.cachedRosters).get(), isEmpty);
    expect(keyStore.key, isNull);
    expect(lastSession.role, isNull);
    expect(summary.saved, isNull);
    expect(
      await container.read(offlineQueueRepositoryProvider).fetchPending(),
      isEmpty,
    );
  }

  test('앱을 켤 때 /me 가 403 으로 거절되면 명단 저장본 · 키 · 요약 · 역할 · 대기열을 지운다', () async {
    final container = build(
      auth: _FailingMe(
        const Failure.api(statusCode: 403, code: 'AUTH_REJECTED', message: 'm'),
      ),
    );
    await seedDeviceState(container);

    await container.read(authBootstrapProvider.future);

    await expectEverythingForgotten(container);
  });

  test('운행 중 게이트(AUTH_PENDING)에 걸리면 명단 저장본 · 키 · 요약 · 역할 · 대기열을 지운다', () async {
    final container = build(adapter: _PendingAdapter())
      ..read(routerRefreshNotifierProvider);
    await seedDeviceState(container);

    await container
        .read(apiClientProvider)
        .dio
        .get<dynamic>('/x')
        .then<void>((_) {}, onError: (_) {});

    await expectEverythingForgotten(container);
  });
}
