import 'dart:async';
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
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/last_session_store.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/launcher/device_launchers.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/home/data/run_summary_store.dart';
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:manager_app/features/offline_queue/data/unsent_emergency_store.dart';
import 'package:manager_app/features/offline_queue/presentation/request_notices.dart';

import '../../support/fake_academy_contact_store.dart';
import '../../support/fake_last_session_store.dart';
import '../../support/fake_roster_key_store.dart';
import '../../support/fake_run_summary_store.dart';
import '../../support/fake_token_storage.dart';
import '../../support/fake_unsent_emergency_store.dart';
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

/// 모든 요청(재발급 포함)에 `401` 을 돌려주는 어댑터 — 앱 시작 `/me` 401 + 재발급 401(세션 만료) 상황.
class _UnauthorizedAdapter implements HttpClientAdapter {
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

/// 쓰기가 [gate] 가 풀릴 때까지 끝나지 않는 비상 안내 저장소.
class _GatedUnsentStore extends FakeUnsentEmergencyStore {
  new(this.gate);

  final Completer<void> gate;

  @override
  Future<void> write(UnsentEmergency value) async {
    await gate.future;
    saved = value;
  }
}

/// R52 최종 대조 — 서버가 계정을 **긍정으로 거절**했다는 증거(부트스트랩 `/me` 403 · 대기·거절 게이트)가 있으면
/// 로그아웃과 같은 범위(명단 저장본 · 암호 키 · 회차 요약 · 저장 역할 · 대기열)를 지운다(NFR-08).
void main() {
  late OfflineQueueDatabase database;
  late FakeRosterKeyStore keyStore;
  late FakeLastSessionStore lastSession;
  late FakeRunSummaryStore summary;
  late FakeTokenStorage tokens;
  late FakeUnsentEmergencyStore unsent;
  late FakeUnsentEmergencyStore droppedTally;

  setUp(() {
    database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
    keyStore = FakeRosterKeyStore();
    lastSession = FakeLastSessionStore(AccountRole.driver);
    summary = FakeRunSummaryStore((
      savedAt: DateTime(2026, 10, 10, 9),
      runs: [managerRunFixture()],
    ));
    tokens = FakeTokenStorage(seedRefreshToken: 'r', seedAccessToken: 'a');
    unsent = FakeUnsentEmergencyStore();
    droppedTally = FakeUnsentEmergencyStore();
  });

  tearDown(() => database.close());

  ProviderContainer build({
    AuthRepository? auth,
    HttpClientAdapter? adapter,
    AcademyContactStore? contacts,
    List<Uri>? opened,
  }) {
    final container = ProviderContainer(
      overrides: [
        tokenStorageProvider.overrideWithValue(tokens),
        offlineQueueDatabaseProvider.overrideWithValue(database),
        rosterKeyStoreProvider.overrideWithValue(keyStore),
        lastSessionStoreProvider.overrideWithValue(lastSession),
        runSummaryStoreProvider.overrideWithValue(summary),
        unsentEmergencyStoreProvider.overrideWithValue(unsent),
        droppedTallyStoreProvider.overrideWithValue(droppedTally),
        academyContactStoreProvider.overrideWithValue(
          contacts ?? FakeAcademyContactStore(),
        ),
        if (opened != null)
          uriOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        if (auth != null) authRepositoryProvider.overrideWithValue(auth),
        if (adapter != null)
          apiClientProvider.overrideWith(
            (ref) => ApiClient(
              tokenStorage: tokens,
              baseUrl: 'https://example.invalid',
              dio: Dio(BaseOptions(baseUrl: 'https://example.invalid'))
                ..httpClientAdapter = adapter,
              // 재발급도 같은 어댑터로 — 기본값이면 실제 네트워크로 나간다.
              refreshDio: Dio(BaseOptions(baseUrl: 'https://example.invalid'))
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

  /// 비상 신고 한 건을 더 쌓는다 — 서버에 닿지 못한 채 기기에만 있는 신고.
  Future<void> queueEmergency(ProviderContainer container) => container
      .read(offlineQueueRepositoryProvider)
      .sendOrQueue<void>(
        endpoint: '/runs/run-A/emergency',
        method: 'POST',
        payload: const {'client_key': 'E', 'type': 'accident'},
        // Failure 는 Exception/Error 를 상속하지 않는다.
        // ignore: only_throw_errors
        send: () => throw const Failure.network(),
      );

  // Ruling 882 — 로그인 화면의 만료 안내가 건수를 알리지 못하는 두 경로(앱 시작 /me 403 · 대기·거절 게이트)도
  // 지운 건수와 "비상은 학원에 직접" 안내를 앱 맨 위에 남긴다.
  test('앱을 켤 때 /me 403 으로 정리하면 버려진 처리 건수와 비상 신고 안내가 남는다', () async {
    final container = build(
      auth: _FailingMe(
        const Failure.api(statusCode: 403, code: 'AUTH_REJECTED', message: 'm'),
      ),
    );
    await seedDeviceState(container);
    await queueEmergency(container);

    await container.read(authBootstrapProvider.future);
    await expectEverythingForgotten(container);

    // 승하차 1건은 메모리 안내, 비상 신고 1건은 기기에 남기는 안내(Ruling 886).
    expect(container.read(requestNoticesProvider).single.title, contains('1건'));
    expect(container.read(unsentEmergencyProvider)?.count, 1);
    expect(unsent.saved?.count, 1);
  });

  // R56 t4 · R55 ② — 앱 시작 `/me` 403 정리 안내(`보내지 못한 처리 N건이 지워졌어요`)가 메모리뿐이라 앱을 껐다 켜면 사라졌다.
  // 건수와 마지막 시각만 기기에 남긴다(892 와 같은 방식 — 학생 이름은 남기지 않는다).
  test('/me 403 정리 안내의 건수와 시각이 기기에 남아 앱을 다시 켜도 이름 없이 남는다', () async {
    final container = build(
      auth: _FailingMe(
        const Failure.api(statusCode: 403, code: 'AUTH_REJECTED', message: 'm'),
      ),
    );
    await seedDeviceState(container);
    await container
        .read(offlineQueueRepositoryProvider)
        .sendOrQueue<void>(
          endpoint: '/runs/run-A/riders/8',
          method: 'PATCH',
          payload: const {'client_key': 'K2', 'status': 'boarded'},
          // Failure 는 Exception/Error 를 상속하지 않는다.
          // ignore: only_throw_errors
          send: () => throw const Failure.network(),
        );

    await container.read(authBootstrapProvider.future);
    await expectEverythingForgotten(container);

    expect(droppedTally.saved?.count, 2);
    expect(droppedTally.saved?.toJson().keys, {'count', 'last_at', 'contact'});
    expect(droppedTally.saved?.contact, isNull);

    // 앱을 껐다 켠다 — 같은 기기 저장소를 넘긴 새 컨테이너.
    final restarted = build()..read(droppedTallyProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(restarted.read(droppedTallyProvider)?.count, 2);
    expect(restarted.read(requestNoticesProvider), isEmpty);
  });

  test('/me 403 정리 안내를 확인하면 기기에 남긴 건수도 그 안내가 센 만큼 줄어든다', () async {
    final container = build(
      auth: _FailingMe(
        const Failure.api(statusCode: 403, code: 'AUTH_REJECTED', message: 'm'),
      ),
    );
    await seedDeviceState(container);
    await container.read(authBootstrapProvider.future);
    await expectEverythingForgotten(container);
    final notice = container.read(requestNoticesProvider).single;
    expect(container.read(droppedTallyProvider)?.count, 1);

    container.read(requestNoticesProvider.notifier).dismiss(notice.id);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(container.read(droppedTallyProvider), isNull);
    expect(droppedTally.saved, isNull);
  });

  test('대기·거절 게이트로 정리하면 버려진 처리 건수와 비상 신고 안내가 남는다', () async {
    final container = build(adapter: _PendingAdapter())
      ..read(routerRefreshNotifierProvider);
    await seedDeviceState(container);
    await queueEmergency(container);

    await container
        .read(apiClientProvider)
        .dio
        .get<dynamic>('/x')
        .then<void>((_) {}, onError: (_) {});
    await expectEverythingForgotten(container);

    expect(container.read(requestNoticesProvider).single.title, contains('1건'));
    expect(container.read(unsentEmergencyProvider)?.count, 1);
  });

  test('버릴 처리가 없으면 안내를 남기지 않는다', () async {
    final container = build(
      auth: _FailingMe(
        const Failure.api(statusCode: 403, code: 'AUTH_REJECTED', message: 'm'),
      ),
    );

    await container.read(authBootstrapProvider.future);
    await expectEverythingForgotten(container);

    expect(container.read(requestNoticesProvider), isEmpty);
    expect(container.read(unsentEmergencyProvider), isNull);
  });

  // Ruling 886 — 앞 계정의 승하차 안내(학생 이름)는 다음 계정에 보이지 않게 비우고, 학생 이름이 없는 비상 안내는 남긴다.
  test('계정 정리 뒤 지운 처리 안내는 비고 비상 신고 안내는 남는다', () async {
    final container = build()..read(routerRefreshNotifierProvider);
    container.read(currentUserRoleProvider.notifier).state = UserRole.driver;
    DroppedRequest dropped(String endpoint) => DroppedRequest(
      request: PendingRequestSummary(
        id: 1,
        endpoint: endpoint,
        method: 'POST',
        payload: '{}',
        createdAt: DateTime(2026, 10, 11),
      ),
      statusCode: 403,
      code: 'FORBIDDEN',
      message: 'm',
    );
    container.read(requestNoticesProvider.notifier).addDropped([
      dropped('/runs/run-A/riders/7'),
      dropped('/runs/run-A/emergency'),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(requestNoticesProvider), hasLength(1));
    expect(container.read(unsentEmergencyProvider)?.count, 1);

    container.read(currentUserRoleProvider.notifier).state = null;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(container.read(requestNoticesProvider), isEmpty);
    expect(container.read(unsentEmergencyProvider)?.count, 1);
    expect(unsent.saved?.count, 1);
  });

  // R53 F2 — 앱 시작 `/me` 401 + 재발급 401 이면 세션 만료 구독과 부트스트랩 두 경로가 모두 계정 정리를 부른다.
  // 정리가 한 번만 돌아야 같은 비상 신고 행이 두 번 세어지지 않는다.
  test('/me 401 + 재발급 401 로 두 정리 경로가 겹쳐도 비상 신고는 한 번만 센다', () async {
    final container = build(adapter: _UnauthorizedAdapter())
      ..read(routerRefreshNotifierProvider);
    await queueEmergency(container);

    await container
        .read(authBootstrapProvider.future)
        .then<void>((_) {}, onError: (_) {});
    await expectEverythingForgotten(container);

    expect(container.read(unsentEmergencyProvider)?.count, 1);
    expect(unsent.saved?.count, 1);
  });

  // R53 B-6② — 비상 건수 저장이 끝나기 전에 대기열을 비우면 그 사이 프로세스가 죽을 때 행도 안내도 남지 않는다.
  test('비상 신고 건수 기기 저장이 끝난 뒤에야 대기열을 비운다', () async {
    final gate = Completer<void>();
    unsent = _GatedUnsentStore(gate);
    final container = build(
      auth: _FailingMe(
        const Failure.api(statusCode: 403, code: 'AUTH_REJECTED', message: 'm'),
      ),
    );
    await queueEmergency(container);

    await container.read(authBootstrapProvider.future);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(
      await container.read(offlineQueueRepositoryProvider).fetchPending(),
      hasLength(1),
      reason: '저장이 끝나기 전에는 대기열이 그대로여야 한다',
    );

    gate.complete();
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(
      await container.read(offlineQueueRepositoryProvider).fetchPending(),
      isEmpty,
    );
    expect(unsent.saved?.count, 1);
  });

  // 안내의 학원 전화 단추 — 번호는 기기에 저장된 학원 연락처에서 온다(정리 때 메모리 번호는 이미 비었다).
  group('정리 안내의 학원 전화 단추', () {
    final tel = Uri(scheme: 'tel', path: '032-000-1100');

    Future<void> tapCallButton(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => RequestNoticesHost(child: child!),
            home: const Scaffold(body: Text('본 화면')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('전화'));
      await tester.pump();
    }

    testWidgets('앱을 켤 때 /me 403 으로 정리하면 학원 전화 단추가 번호를 연다', (tester) async {
      final opened = <Uri>[];
      final container = build(
        auth: _FailingMe(
          const Failure.api(
            statusCode: 403,
            code: 'AUTH_REJECTED',
            message: 'm',
          ),
        ),
        contacts: FakeAcademyContactStore('032-000-1100'),
        opened: opened,
      );
      await tester.runAsync(() async {
        await seedDeviceState(container);
        await queueEmergency(container);
        await container.read(authBootstrapProvider.future);
        await expectEverythingForgotten(container);
      });

      await tapCallButton(tester, container);

      expect(opened, [tel]);
    });

    testWidgets('대기·거절 게이트로 정리하면 학원 전화 단추가 번호를 연다', (tester) async {
      final opened = <Uri>[];
      // 게이트 이벤트는 스트림이라 실제 시계 구역에서 만들고 돌려야 전달된다.
      late ProviderContainer container;
      await tester.runAsync(() async {
        container = build(
          adapter: _PendingAdapter(),
          contacts: FakeAcademyContactStore('032-000-1100'),
          opened: opened,
        )..read(routerRefreshNotifierProvider);
        await seedDeviceState(container);
        await queueEmergency(container);
        await container
            .read(apiClientProvider)
            .dio
            .get<dynamic>('/x')
            .then<void>((_) {}, onError: (_) {});
        await expectEverythingForgotten(container);
      });

      await tapCallButton(tester, container);

      expect(opened, [tel]);
    });
  });
}
