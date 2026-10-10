import 'package:baraeda_core/baraeda_core.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/app.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/academy_contact_store.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/last_session_store.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/auth/presentation/login_screen.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/data/run_summary_store.dart';
import 'package:manager_app/features/home/domain/manager_run_repository.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_auto_sync.dart';

import '../../support/fake_academy_contact_store.dart';
import '../../support/fake_last_session_store.dart';
import '../../support/fake_notification_repository.dart';
import '../../support/fake_roster_key_store.dart';
import '../../support/fake_run_summary_store.dart';
import '../../support/fake_token_storage.dart';
import '../../support/manager_run_fixture.dart';

/// 회차 목록은 비어 있다 — 기사 계정이 확인되면 앱이 위치 송신 재개용으로 목록을 한 번 부른다.
class _NoRuns implements ManagerRunRepository {
  @override
  Future<List<ManagerRun>> fetchRuns({DateTime? date}) async => const [];
}

/// [failure] 가 있는 동안 `/me` 가 그 오류로 실패하고, `null` 로 바꾸면(연결 회복) 기사 계정을 돌려주는 가짜.
class _MeRepository implements AuthRepository {
  new(this.failure);

  Failure? failure;

  @override
  Future<MeResponse> me() async {
    final error = failure;
    if (error != null) return await Future<MeResponse>.error(error);
    return const MeResponse(
      accountId: 'a-1',
      loginId: 'driverA1',
      name: '기사',
      phone: '010',
      role: AccountRole.driver,
      status: AccountStatus.active,
    );
  }

  @override
  Future<LoginResponse> login({
    required String loginId,
    required String password,
  }) async => const LoginResponse(
    accessToken: 'a',
    role: AccountRole.driver,
    status: AccountStatus.active,
    accountId: 'a-1',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// R52 H2 — 통신이 끊긴 채 앱을 새로 켜도 마지막으로 확인한 역할로 들어가 저장 명단 · 대기열 · 비상 · 학원 전화가
/// 열려야 한다(NFR-01 · M-06). 인증 거절(401)은 지금처럼 로그인 화면이다.
void main() {
  const network = Failure.network();
  const rejected = Failure.api(statusCode: 401, code: 'AUTH', message: '만료');
  // nginx · Cloudflare Tunnel 이 서버가 죽었을 때 내는 HTML 오류 페이지 — JSON 이 아니라 `unknown` 으로 매핑된다.
  const gatewayHtml = Failure.unknown(
    message: '서버 응답을 해석할 수 없음 (status: 502)',
    statusCode: 502,
  );

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    required _MeRepository repository,
    required FakeLastSessionStore store,
    FakeRunSummaryStore? summary,
  }) async {
    late ProviderContainer container;
    // 세션 종료가 대기열을 비울 때 실제 파일 DB 를 열지 않게 메모리 DB 를 쓰고, 시험이 끝나면 닫는다(drift 다중 생성 경고 방지).
    final queueDatabase = OfflineQueueDatabase.forTesting(
      NativeDatabase.memory(),
    );
    addTearDown(queueDatabase.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(
            FakeTokenStorage(seedRefreshToken: 'refresh'),
          ),
          authRepositoryProvider.overrideWithValue(repository),
          offlineQueueDatabaseProvider.overrideWithValue(queueDatabase),
          lastSessionStoreProvider.overrideWithValue(store),
          if (summary != null)
            runSummaryStoreProvider.overrideWithValue(summary),
          academyContactStoreProvider.overrideWithValue(
            FakeAcademyContactStore(),
          ),
          managerRunRepositoryProvider.overrideWithValue(_NoRuns()),
          todayRunsProvider.overrideWith((ref) async => []),
          notificationRepositoryProvider.overrideWithValue(
            FakeNotificationRepository(const []),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const BaraedaManagerApp();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('저장 역할이 있고 /me 가 연결 실패면 오류 화면 대신 홈이 열린다', (tester) async {
    final store = FakeLastSessionStore(AccountRole.driver);
    final container = await pumpApp(
      tester,
      repository: _MeRepository(network),
      store: store,
    );

    expect(find.text('네트워크 상태를 확인해 주세요'), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('오늘 운행'), findsOneWidget);
    expect(container.read(currentUserRoleProvider), UserRole.driver);
    expect(container.read(unverifiedSessionProvider), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('서버 오류(5xx)도 저장 역할이 있으면 홈이 열린다', (tester) async {
    await pumpApp(
      tester,
      repository: _MeRepository(
        const Failure.api(statusCode: 503, code: 'X', message: 'down'),
      ),
      store: FakeLastSessionStore(AccountRole.driver),
    );

    expect(find.text('오늘 운행'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('저장 역할이 없으면 지금처럼 다시 시도 안내를 보인다', (tester) async {
    await pumpApp(
      tester,
      repository: _MeRepository(network),
      store: FakeLastSessionStore(),
    );

    expect(find.text('네트워크 상태를 확인해 주세요'), findsOneWidget);
    expect(find.text('오늘 운행'), findsNothing);
  });

  testWidgets('인증 거절(401)이면 저장 역할이 있어도 로그인 화면이고 저장 역할을 지운다', (tester) async {
    final store = FakeLastSessionStore(AccountRole.driver);
    await pumpApp(tester, repository: _MeRepository(rejected), store: store);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('오늘 운행'), findsNothing);
    expect(store.role, isNull);
  });

  testWidgets('/me 가 성공하면 역할을 기기에 남긴다', (tester) async {
    final store = FakeLastSessionStore();
    await pumpApp(tester, repository: _MeRepository(null), store: store);

    expect(store.role, AccountRole.driver);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('연결이 돌아오면 /me 를 다시 불러 확인된 세션으로 바꾼다', (tester) async {
    final repository = _MeRepository(network);
    final container = await pumpApp(
      tester,
      repository: repository,
      store: FakeLastSessionStore(AccountRole.driver),
    );
    expect(container.read(unverifiedSessionProvider), isTrue);

    repository.failure = null;
    await container.read(sessionReverifierProvider)();

    expect(container.read(unverifiedSessionProvider), isFalse);
    expect(container.read(currentUserRoleProvider), UserRole.driver);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('연결이 돌아온 뒤 30초 주기가 오면 앱이 스스로 /me 를 다시 확인한다', (tester) async {
    final repository = _MeRepository(network);
    final container = await pumpApp(
      tester,
      repository: repository,
      store: FakeLastSessionStore(AccountRole.driver),
    );
    expect(container.read(unverifiedSessionProvider), isTrue);

    repository.failure = null;
    await tester.pump(OfflineQueueAutoSync.interval);
    await tester.pump();

    expect(container.read(unverifiedSessionProvider), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('다시 확인할 때도 닿지 않으면 마지막 역할 그대로 둔다', (tester) async {
    final repository = _MeRepository(network);
    final container = await pumpApp(
      tester,
      repository: repository,
      store: FakeLastSessionStore(AccountRole.driver),
    );

    await container.read(sessionReverifierProvider)();

    expect(container.read(unverifiedSessionProvider), isTrue);
    expect(container.read(currentUserRoleProvider), UserRole.driver);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('다시 확인이 서버의 거절(403)이면 저장 역할을 지우고 세션을 끝낸다', (tester) async {
    const blocked = Failure.api(
      statusCode: 403,
      code: 'AUTH_ACCOUNT_BLOCKED',
      message: '차단',
    );
    final repository = _MeRepository(network);
    final store = FakeLastSessionStore(AccountRole.driver);
    final container = await pumpApp(
      tester,
      repository: repository,
      store: store,
    );
    expect(container.read(unverifiedSessionProvider), isTrue);

    repository.failure = blocked;
    await container.read(sessionReverifierProvider)();
    await tester.pumpAndSettle();

    expect(store.role, isNull);
    expect(container.read(currentUserRoleProvider), isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('다시 확인이 서버의 거절(401)이어도 저장 역할을 지운다', (tester) async {
    final repository = _MeRepository(network);
    final store = FakeLastSessionStore(AccountRole.driver);
    final container = await pumpApp(
      tester,
      repository: repository,
      store: store,
    );

    repository.failure = rejected;
    await container.read(sessionReverifierProvider)();
    await tester.pumpAndSettle();

    expect(store.role, isNull);
  });

  testWidgets('게이트웨이 HTML 502 도 연결 두절처럼 저장 역할로 홈이 열린다', (tester) async {
    final container = await pumpApp(
      tester,
      repository: _MeRepository(gatewayHtml),
      store: FakeLastSessionStore(AccountRole.driver),
    );

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('오늘 운행'), findsOneWidget);
    expect(container.read(unverifiedSessionProvider), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('시작할 때 서버가 JSON 으로 거절(403)하면 저장 역할 · 요약을 지우고 로그인 화면이다', (
    tester,
  ) async {
    final store = FakeLastSessionStore(AccountRole.driver);
    final summary = FakeRunSummaryStore((
      savedAt: DateTime(2026, 10, 10, 9),
      runs: [managerRunFixture()],
    ));
    await pumpApp(
      tester,
      repository: _MeRepository(
        const Failure.api(
          statusCode: 403,
          code: 'AUTH_ACCOUNT_BLOCKED',
          message: '차단',
        ),
      ),
      store: store,
      summary: summary,
    );

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(store.role, isNull);
    expect(summary.saved, isNull);
  });

  // 서버가 이 계정을 거절했다는 긍정 증거가 없는 실패는 세션 · 저장분을 그대로 둔다 — 지우면 대기열(비상 신고 포함)까지
  // 버려지는 로그아웃이 된다.
  for (final (label, failure) in <(String, Failure)>[
    ('게이트웨이 HTML 502', gatewayHtml),
    ('HTML 504 (Failure.unknown)', const Failure.unknown(statusCode: 504)),
    ('응답 없는 기타 오류', const Failure.unknown()),
    ('서버 오류 500', Failure.api(statusCode: 500, code: 'X', message: 'm')),
    ('연결 두절', network),
  ]) {
    testWidgets('다시 확인이 $label 이면 세션 · 저장 역할 · 요약을 그대로 둔다', (tester) async {
      final repository = _MeRepository(network);
      final store = FakeLastSessionStore(AccountRole.driver);
      final summary = FakeRunSummaryStore((
        savedAt: DateTime(2026, 10, 10, 9),
        runs: [managerRunFixture()],
      ));
      final container = await pumpApp(
        tester,
        repository: repository,
        store: store,
        summary: summary,
      );

      repository.failure = failure;
      await container.read(sessionReverifierProvider)();
      await tester.pumpAndSettle();

      expect(container.read(currentUserRoleProvider), UserRole.driver);
      expect(container.read(unverifiedSessionProvider), isTrue);
      expect(store.role, AccountRole.driver);
      expect(summary.saved, isNotNull);
      expect(find.byType(LoginScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('로그인에 성공하면 역할을 기기에 남긴다', (tester) async {
    final store = FakeLastSessionStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_MeRepository(network)),
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

    expect(store.role, AccountRole.driver);
  });

  test('로그아웃(역할이 비는 순간)하면 저장한 역할을 지운다', () async {
    final database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
    final store = FakeLastSessionStore(AccountRole.driver);
    final summary = FakeRunSummaryStore((
      savedAt: DateTime(2026, 10, 10, 9),
      runs: [managerRunFixture()],
    ));
    final container = ProviderContainer(
      overrides: [
        runSummaryStoreProvider.overrideWithValue(summary),
        tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
        offlineQueueDatabaseProvider.overrideWithValue(database),
        rosterKeyStoreProvider.overrideWithValue(FakeRosterKeyStore()),
        lastSessionStoreProvider.overrideWithValue(store),
        todayRunsProvider.overrideWith((ref) async => []),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });
    container.read(routerRefreshNotifierProvider);
    container.read(currentUserRoleProvider.notifier).state = UserRole.driver;

    container.read(currentUserRoleProvider.notifier).state = null;
    await Future<void>.delayed(Duration.zero);

    expect(store.role, isNull);
    expect(summary.saved, isNull, reason: '오늘 회차 요약도 함께 지운다');
  });
}
