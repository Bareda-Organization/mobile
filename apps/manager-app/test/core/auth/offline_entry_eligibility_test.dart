import 'dart:typed_data';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/academy_contact_store.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/last_session_store.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/auth/presentation/login_screen.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/data/run_summary_store.dart';
import 'package:manager_app/features/home/domain/manager_run_repository.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';

import '../../support/fake_academy_contact_store.dart';
import '../../support/fake_last_session_store.dart';
import '../../support/fake_roster_key_store.dart';
import '../../support/fake_run_summary_store.dart';
import '../../support/fake_token_storage.dart';
import '../../support/manager_run_fixture.dart';

class _NoRuns implements ManagerRunRepository {
  @override
  Future<List<ManagerRun>> fetchRuns({DateTime? date}) async => const [];
}

/// `/me` · 로그인이 [me] 를 그대로 돌려주는 가짜.
class _Auth implements AuthRepository {
  new(this.me_);

  final MeResponse me_;

  @override
  Future<MeResponse> me() async => me_;

  @override
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  }) async => LoginResponse(
    accessToken: 'a',
    role: me_.role,
    status: me_.status,
    accountId: 'a-1',
    mustChangePassword: me_.mustChangePassword,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

MeResponse _me(
  AccountRole role,
  AccountStatus status, {
  bool mustChangePassword = false,
}) => MeResponse(
  accountId: 'a-1',
  loginId: 'id',
  name: '이름',
  phone: '010',
  role: role,
  status: status,
  mustChangePassword: mustChangePassword,
);

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

/// R52 H2(수정 라운드 1) — 오프라인으로 들어갈 자격은 **활성 · 지원 역할 · 임시 비밀번호 아님** 뿐이다. 그 밖의 계정은
/// 기기에 역할이 남지 않고, 운행 중 게이트(대기 · 거절)에 걸리면 남아 있던 역할 · 회차 요약도 지운다.
void main() {
  Future<FakeLastSessionStore> bootstrapWith(MeResponse me) async {
    final store = FakeLastSessionStore();
    final container = ProviderContainer(
      overrides: [
        tokenStorageProvider.overrideWithValue(
          FakeTokenStorage(seedRefreshToken: 'refresh'),
        ),
        authRepositoryProvider.overrideWithValue(_Auth(me)),
        lastSessionStoreProvider.overrideWithValue(store),
        academyContactStoreProvider.overrideWithValue(
          FakeAcademyContactStore(),
        ),
        runSummaryStoreProvider.overrideWithValue(FakeRunSummaryStore()),
        managerRunRepositoryProvider.overrideWithValue(_NoRuns()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authBootstrapProvider.future);
    await Future<void>.delayed(Duration.zero);
    return store;
  }

  test('활성 기사는 역할이 남는다(기준)', () async {
    final store = await bootstrapWith(
      _me(AccountRole.driver, AccountStatus.active),
    );
    expect(store.role, AccountRole.driver);
  });

  test('승인 대기 계정은 오프라인 입장용 역할이 남지 않는다', () async {
    final store = await bootstrapWith(
      _me(AccountRole.driver, AccountStatus.pending),
    );
    expect(store.role, isNull);
  });

  test('가입 거절 계정은 오프라인 입장용 역할이 남지 않는다', () async {
    final store = await bootstrapWith(
      _me(AccountRole.escort, AccountStatus.rejected),
    );
    expect(store.role, isNull);
  });

  test('이 앱이 지원하지 않는 역할은 오프라인 입장용 역할이 남지 않는다', () async {
    final store = await bootstrapWith(
      _me(AccountRole.parent, AccountStatus.active),
    );
    expect(store.role, isNull);
  });

  test('임시 비밀번호 상태(/me)면 오프라인 입장용 역할이 남지 않는다', () async {
    final store = await bootstrapWith(
      _me(AccountRole.driver, AccountStatus.active, mustChangePassword: true),
    );
    expect(store.role, isNull);
  });

  testWidgets('임시 비밀번호 상태로 로그인해도 역할이 남지 않는다', (tester) async {
    final store = FakeLastSessionStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _Auth(
              _me(
                AccountRole.driver,
                AccountStatus.active,
                mustChangePassword: true,
              ),
            ),
          ),
          lastSessionStoreProvider.overrideWithValue(store),
          academyContactStoreProvider.overrideWithValue(
            FakeAcademyContactStore(),
          ),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.enterText(find.byType(TextField).at(0), 'driverA1');
    await tester.enterText(find.byType(TextField).at(1), 'password');
    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();

    expect(store.role, isNull);
  });

  test('운행 중 게이트(AUTH_PENDING)에 걸리면 기억한 역할과 회차 요약을 지운다', () async {
    final database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
    final store = FakeLastSessionStore(AccountRole.driver);
    final summary = FakeRunSummaryStore((
      savedAt: DateTime(2026, 10, 10, 9),
      runs: [managerRunFixture()],
    ));
    final tokens = FakeTokenStorage(
      seedRefreshToken: 'r',
      seedAccessToken: 'a',
    );
    final container = ProviderContainer(
      overrides: [
        tokenStorageProvider.overrideWithValue(tokens),
        offlineQueueDatabaseProvider.overrideWithValue(database),
        rosterKeyStoreProvider.overrideWithValue(FakeRosterKeyStore()),
        lastSessionStoreProvider.overrideWithValue(store),
        runSummaryStoreProvider.overrideWithValue(summary),
        managerRunRepositoryProvider.overrideWithValue(_NoRuns()),
        apiClientProvider.overrideWith(
          (ref) => ApiClient(
            tokenStorage: tokens,
            baseUrl: 'https://example.invalid',
            dio: Dio(BaseOptions(baseUrl: 'https://example.invalid'))
              ..httpClientAdapter = _PendingAdapter(),
          ),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });
    container.read(routerRefreshNotifierProvider);

    await container
        .read(apiClientProvider)
        .dio
        .get<dynamic>('/x')
        .then<void>((_) {}, onError: (_) {});
    await Future<void>.delayed(Duration.zero);

    expect(store.role, isNull);
    expect(summary.saved, isNull);
  });
}
