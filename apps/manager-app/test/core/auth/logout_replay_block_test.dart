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
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/home/data/run_summary_store.dart';
import 'package:manager_app/features/offline_queue/data/offline_queue_database.dart';
import 'package:manager_app/features/offline_queue/data/unsent_emergency_store.dart';

import '../../support/fake_academy_contact_store.dart';
import '../../support/fake_last_session_store.dart';
import '../../support/fake_roster_key_store.dart';
import '../../support/fake_run_summary_store.dart';
import '../../support/fake_token_storage.dart';
import '../../support/fake_unsent_emergency_store.dart';

/// 요청이 나갈 때마다 세고 `200` 으로 답한다.
class _CountingAdapter implements HttpClientAdapter {
  int requests = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

/// `logout` 이 [gate] 가 풀릴 때까지 끝나지 않는 가짜 — 로그아웃이 시작됐지만
/// 아직 대기열이 비워지지 않은 구간을 만든다.
/// [gate] 는 `runAsync` 안에서 만들어야 한다(가짜 시계 영역에서 만든 Completer 는 pump 전에는 이어지지 않는다).
class _GatedLogoutAuth implements AuthRepository {
  late Completer<void> gate;

  @override
  Future<void> logout() => gate.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// R56 · R55 ③ — 로그아웃이 시작되고 대기열이 비워지기까지 사이에 재생이 시작되면 앞 계정의 처리가 전송된다.
/// 로그아웃이 시작되면 새 재생 시작을 막는다(이미 나간 요청 1건은 막을 수 없다).
void main() {
  late OfflineQueueDatabase database;
  late _CountingAdapter adapter;
  late WidgetRef capturedRef;

  setUp(() {
    database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
    adapter = _CountingAdapter();
  });
  tearDown(() => database.close());

  Future<ProviderContainer> launch(
    WidgetTester tester,
    AuthRepository auth,
  ) async {
    final tokens = FakeTokenStorage(
      seedRefreshToken: 'r',
      seedAccessToken: 'a',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          offlineQueueDatabaseProvider.overrideWithValue(database),
          tokenStorageProvider.overrideWithValue(tokens),
          rosterKeyStoreProvider.overrideWithValue(FakeRosterKeyStore()),
          lastSessionStoreProvider.overrideWithValue(FakeLastSessionStore()),
          runSummaryStoreProvider.overrideWithValue(FakeRunSummaryStore()),
          unsentEmergencyStoreProvider.overrideWithValue(
            FakeUnsentEmergencyStore(),
          ),
          droppedTallyStoreProvider.overrideWithValue(
            FakeUnsentEmergencyStore(),
          ),
          academyContactStoreProvider.overrideWithValue(
            FakeAcademyContactStore(),
          ),
          authRepositoryProvider.overrideWithValue(auth),
          apiClientProvider.overrideWith(
            (ref) => ApiClient(
              tokenStorage: tokens,
              baseUrl: 'https://example.invalid',
              dio: Dio(BaseOptions(baseUrl: 'https://example.invalid'))
                ..httpClientAdapter = adapter,
              refreshDio: Dio(BaseOptions(baseUrl: 'https://example.invalid'))
                ..httpClientAdapter = adapter,
            ),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const MaterialApp(home: Scaffold(body: Text('본 화면')));
          },
        ),
      ),
    );
    return ProviderScope.containerOf(tester.element(find.text('본 화면')));
  }

  testWidgets('로그아웃이 시작된 뒤에는 재생 요청이 나가지 않고 대기열은 정리된다', (tester) async {
    final auth = _GatedLogoutAuth();
    final container = await launch(tester, auth);
    container.read(routerRefreshNotifierProvider);
    container.read(currentUserRoleProvider.notifier).state = UserRole.driver;

    await tester.runAsync(() async {
      auth.gate = Completer<void>();
      final queue = container.read(offlineQueueRepositoryProvider);
      await queue.sendOrQueue<void>(
        endpoint: '/runs/run-A/riders/7',
        method: 'PATCH',
        payload: const {'client_key': 'K', 'status': 'boarded'},
        // Failure 는 Exception/Error 를 상속하지 않는다.
        // ignore: only_throw_errors
        send: () => throw const Failure.network(),
      );

      // 로그아웃이 시작됐지만(서버 응답 대기) 대기열은 아직 비워지지 않은 구간.
      final signingOut = signOut(capturedRef);
      final replay = await queue.replayPending();
      expect(adapter.requests, 0, reason: '로그아웃이 시작된 뒤 재생이 앞 계정의 처리를 보냈다');
      expect(replay.succeeded, 0);

      auth.gate.complete();
      await signingOut;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(adapter.requests, 0);
      expect(await queue.fetchPending(), isEmpty);
      expect(
        container.read(replayGateProvider).isPaused,
        isFalse,
        reason: '대기열 정리가 끝나면 다음 로그인의 재생을 막지 않는다',
      );
    });
  });
}
