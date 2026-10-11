import 'package:baraeda_core/baraeda_core.dart';
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
import 'package:manager_app/features/offline_queue/domain/offline_queue_repository.dart';
import 'package:manager_app/features/offline_queue/presentation/request_notices.dart';

import '../../support/fake_academy_contact_store.dart';
import '../../support/fake_last_session_store.dart';
import '../../support/fake_roster_key_store.dart';
import '../../support/fake_run_summary_store.dart';
import '../../support/fake_token_storage.dart';
import '../../support/fake_unsent_emergency_store.dart';

class _FixedClock implements Clock {
  const new(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}

class _StubAuthRepository implements AuthRepository {
  @override
  Future<void> logout() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 대기 요청을 비비는 순간([clear])에 기기 저장 안내가 이미 올라와 있는지 보려고 그 시점의 건수를 적어 두는 대기열.
class _RecordingQueue implements OfflineQueueRepository {
  new(this.pending, this.onClear);

  final List<PendingRequestSummary> pending;
  final void Function() onClear;

  @override
  Future<List<PendingRequestSummary>> fetchPending() async => pending;

  @override
  Future<void> clear() async => onClear();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Ruling 886 — 서버가 거절해 지워진 비상 신고의 안내는 사용자가 [확인] 할 때까지 기기에 남는다. 앱 종료 · 세션 만료 ·
/// 로그아웃으로 사라지지 않고, 승하차 행의 안내(학생 이름)는 메모리에만 있어 앱을 다시 켜면 없다.
void main() {
  late OfflineQueueDatabase database;
  late FakeUnsentEmergencyStore store;
  late WidgetRef capturedRef;

  setUp(() {
    database = OfflineQueueDatabase.forTesting(NativeDatabase.memory());
    store = FakeUnsentEmergencyStore();
  });
  tearDown(() => database.close());

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
    message: '서버 문구',
  );

  /// 앱 한 번 켜기 — 같은 [store] 를 넘기면 앱을 껐다 켠 것과 같다(저장소만 살아남는다).
  Future<ProviderContainer> launchApp(
    WidgetTester tester, {
    List<Uri>? opened,
    OfflineQueueRepository? queue,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unsentEmergencyStoreProvider.overrideWithValue(store),
          clockProvider.overrideWithValue(
            _FixedClock(DateTime(2026, 10, 11, 9, 30)),
          ),
          offlineQueueDatabaseProvider.overrideWithValue(database),
          if (queue != null)
            offlineQueueRepositoryProvider.overrideWithValue(queue),
          rosterKeyStoreProvider.overrideWithValue(FakeRosterKeyStore()),
          lastSessionStoreProvider.overrideWithValue(FakeLastSessionStore()),
          runSummaryStoreProvider.overrideWithValue(FakeRunSummaryStore()),
          academyContactStoreProvider.overrideWithValue(
            FakeAcademyContactStore(),
          ),
          authRepositoryProvider.overrideWithValue(_StubAuthRepository()),
          tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          if (opened != null)
            uriOpenerProvider.overrideWithValue((uri) async {
              opened.add(uri);
              return true;
            }),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return MaterialApp(
              builder: (context, child) => RequestNoticesHost(child: child!),
              home: const Scaffold(body: Text('본 화면')),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.text('본 화면')));
  }

  /// 앱을 끈다 — 컨테이너가 버려진다.
  Future<void> quitApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  final bannerText = find.text('이 기기에서 보낸 비상 신고 1건이 전송되지 않았습니다');

  Future<void> rejectEmergency(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    container.read(requestNoticesProvider.notifier).addDropped([
      dropped('/runs/run-A/emergency'),
    ]);
    await tester.pumpAndSettle();
  }

  testWidgets('비상 거절 안내는 앱을 껐다 켜도 남고 저장된 학원 번호로 전화를 건다', (tester) async {
    final opened = <Uri>[];
    var container = await launchApp(tester, opened: opened);
    container.read(academyContactProvider.notifier).state = '032-000-1100';
    await rejectEmergency(tester, container);
    expect(bannerText, findsOneWidget);
    expect(find.textContaining('10월 11일 09:30'), findsOneWidget);

    await quitApp(tester);
    // 새로 켠 앱은 로그인 전이라 메모리의 학원 번호가 없다 — 그때 저장해 둔 번호가 쓰인다.
    container = await launchApp(tester, opened: opened);

    expect(bannerText, findsOneWidget);
    await tester.tap(find.text('전화'));
    await tester.pump();
    expect(opened.single, Uri(scheme: 'tel', path: '032-000-1100'));
  });

  testWidgets('세션이 만료돼 계정을 정리해도 비상 거절 안내가 남는다', (tester) async {
    final container = await launchApp(tester);
    container.read(routerRefreshNotifierProvider);
    container.read(currentUserRoleProvider.notifier).state = UserRole.driver;
    await rejectEmergency(tester, container);

    endSessionAsExpired(container.read(_refProvider));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(container.read(currentUserRoleProvider), isNull);
    expect(bannerText, findsOneWidget);
    expect(store.saved?.count, 1);
  });

  testWidgets('로그아웃해도 비상 거절 안내가 남는다', (tester) async {
    final container = await launchApp(tester);
    container.read(routerRefreshNotifierProvider);
    container.read(currentUserRoleProvider.notifier).state = UserRole.driver;
    await rejectEmergency(tester, container);

    await tester.runAsync(() async {
      await signOut(capturedRef);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(container.read(currentUserRoleProvider), isNull);
    expect(bannerText, findsOneWidget);
    expect(store.saved?.count, 1);
  });

  /// 아직 서버에 가지 못한 채 대기열에 남은 승하차 1건 + 비상 신고 1건.
  Future<void> queueRiderAndEmergency(
    WidgetTester tester,
    ProviderContainer container,
  ) => tester.runAsync(() async {
    for (final (endpoint, payload) in [
      ('/runs/run-A/riders/7', {'client_key': 'K', 'status': 'boarded'}),
      ('/runs/run-A/emergency', {'client_key': 'E', 'type': 'accident'}),
    ]) {
      await container
          .read(offlineQueueRepositoryProvider)
          .sendOrQueue<void>(
            endpoint: endpoint,
            method: 'POST',
            payload: payload,
            // Failure 는 Exception/Error 를 상속하지 않는다.
            // ignore: only_throw_errors
            send: () => throw const Failure.network(),
          );
    }
  });

  /// 대기열째 버려진 뒤 앱을 껐다 켜도 비상 1건만 남고 승하차 건은 세지 않는다(Ruling 886).
  Future<void> expectOnlyEmergencyKeptAfterRestart(WidgetTester tester) async {
    // 저장 쓰기까지 이어 붙은 비동기 작업이 끝나도록 한 번 더 돌린다.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(store.saved?.count, 1);
    await quitApp(tester);
    final container = await launchApp(tester);
    expect(bannerText, findsOneWidget);
    expect(container.read(unsentEmergencyProvider)?.count, 1);
    expect(container.read(requestNoticesProvider), isEmpty);
  }

  testWidgets('세션이 만료돼 대기열이 버려져도 못 보낸 비상 신고 안내가 남고 승하차 건은 세지 않는다', (
    tester,
  ) async {
    final container = await launchApp(tester);
    container.read(routerRefreshNotifierProvider);
    container.read(currentUserRoleProvider.notifier).state = UserRole.driver;
    await queueRiderAndEmergency(tester, container);

    endSessionAsExpired(container.read(_refProvider));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    // 로그인 화면 안내는 건수 · 비상을 자기 문장으로 알리고, 기기 저장 안내는 비상 건만 센다.
    expect(
      container.read(sessionExpiredNoticeProvider),
      allOf(contains('2건'), contains('비상 신고 1건')),
    );
    await expectOnlyEmergencyKeptAfterRestart(tester);
  });

  testWidgets('로그아웃으로 대기열이 버려져도 못 보낸 비상 신고 안내가 남고 승하차 건은 세지 않는다', (
    tester,
  ) async {
    final container = await launchApp(tester);
    container.read(routerRefreshNotifierProvider);
    container.read(currentUserRoleProvider.notifier).state = UserRole.driver;
    await queueRiderAndEmergency(tester, container);

    await tester.runAsync(() async {
      await signOut(capturedRef);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    await expectOnlyEmergencyKeptAfterRestart(tester);
  });

  testWidgets('대기열을 비우기 전에 비상 신고 건수가 먼저 안내에 올라간다(그 사이 앱이 죽어도 안내가 남게)', (
    tester,
  ) async {
    int? countWhenCleared;
    late ProviderContainer container;
    final queue = _RecordingQueue([
      PendingRequestSummary(
        id: 1,
        endpoint: '/runs/run-A/emergency',
        method: 'POST',
        payload: '{}',
        createdAt: DateTime(2026, 10, 11),
      ),
    ], () => countWhenCleared = container.read(unsentEmergencyProvider)?.count);
    container = await launchApp(tester, queue: queue);
    container.read(routerRefreshNotifierProvider);
    container.read(currentUserRoleProvider.notifier).state = UserRole.driver;

    endSessionAsExpired(container.read(_refProvider));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );

    await tester.pumpAndSettle();
    expect(countWhenCleared, 1);
  });

  testWidgets('[확인] 을 누르면 사라지고 다시 켜도 나오지 않는다', (tester) async {
    var container = await launchApp(tester);
    await rejectEmergency(tester, container);

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(bannerText, findsNothing);
    expect(store.saved, isNull);

    await quitApp(tester);
    container = await launchApp(tester);
    expect(bannerText, findsNothing);
  });

  testWidgets('거절이 거듭되면 건수가 더해진다', (tester) async {
    final container = await launchApp(tester);
    await rejectEmergency(tester, container);
    await rejectEmergency(tester, container);

    expect(find.text('이 기기에서 보낸 비상 신고 2건이 전송되지 않았습니다'), findsOneWidget);
  });

  testWidgets('승하차 행 안내는 앱을 다시 켜면 없다(메모리에만 둔다)', (tester) async {
    var container = await launchApp(tester);
    container.read(requestNoticesProvider.notifier).addDropped([
      dropped('/runs/run-A/riders/7'),
    ]);
    await tester.pumpAndSettle();
    expect(find.textContaining('서버로 보내지 못하고'), findsOneWidget);

    await quitApp(tester);
    container = await launchApp(tester);

    expect(find.textContaining('서버로 보내지 못하고'), findsNothing);
    expect(container.read(requestNoticesProvider), isEmpty);
  });
}

/// 세션 만료 함수가 요구하는 `Ref` 를 시험에서 꺼내는 통로.
final _refProvider = Provider<Ref>((ref) => ref);
