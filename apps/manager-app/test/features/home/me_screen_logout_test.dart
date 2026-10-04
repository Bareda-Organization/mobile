import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/app.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/auth/presentation/login_screen.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/home/presentation/me_screen.dart';
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/domain/offline_queue_repository.dart';

import '../../support/fake_token_storage.dart';

/// `logout` 만 쓰는 가짜 — `sign_out_test.dart` 의 `_StubAuthRepository` 와
/// 같은 패턴. 나머지 메서드는 이 시험에서 불리면 안 된다.
class _StubAuthRepository implements AuthRepository {
  new({this.fail = false});

  final bool fail;
  int logoutCalls = 0;

  @override
  Future<void> logout() async {
    logoutCalls++;
    if (fail) throw Exception('network down');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 대기 목록만 쓰는 가짜 — 로그아웃 확인 창이 미전송 건수를 세는 데만 쓴다(M2-01).
class _StubQueueRepository implements OfflineQueueRepository {
  new(this.pendingCount);

  final int pendingCount;

  @override
  Future<List<PendingRequestSummary>> fetchPending() async => List.generate(
    pendingCount,
    (i) => PendingRequestSummary(
      id: i,
      endpoint: '/runs/run-1/riders/$i',
      method: 'PATCH',
      payload: '{}',
      createdAt: DateTime(2026, 9, 26, 8),
    ),
  );

  /// 로그아웃하면 대기열을 비운다(F06-02) — 여기서는 아무것도 하지 않는다.
  @override
  Future<void> clear() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ManagerRun _run({required RunStatus runStatus}) {
  final now = DateTime(2026, 9, 26, 8);
  return ManagerRun(
    runId: 'run-1',
    busNo: '3호차',
    direction: RunDirection.toAcademy,
    departTime: now,
    origin: '기점',
    destination: '학원',
    estDurationMin: 30,
    runStatus: runStatus,
    confirmed: true,
    startWindowFrom: now.subtract(const Duration(minutes: 10)),
    startWindowTo: now.add(const Duration(minutes: 10)),
    addedCount: 0,
    removedCount: 0,
    ackRequired: false,
  );
}

/// 로그아웃(AUTH-09) — 기사·동승자 둘 다 닿는 내 정보 탭 맨 아래 단추(`Ruling 826`).
/// `BaraedaManagerApp` 전체를 띄워 실제 `routerProvider` 의 redirect 가
/// 로그인 화면으로 보내는지까지 확인한다(`router_redirect_test.dart` 와
/// 같은 이유 — 확인 대화만 위젯 트리 일부로 시험하면 "그래서 실제로 로그인
/// 화면으로 가는가" 를 놓친다).
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required AuthRepository authRepository,
    RunStatus? extraMovingRun,
    int pendingCount = 0,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
          currentAccountStatusProvider.overrideWith(
            (ref) => AccountStatus.active,
          ),
          authRepositoryProvider.overrideWithValue(authRepository),
          offlineQueueRepositoryProvider.overrideWithValue(
            _StubQueueRepository(pendingCount),
          ),
          todayRunsProvider.overrideWith(
            (ref) async => [
              _run(runStatus: extraMovingRun ?? RunStatus.confirmed),
            ],
          ),
        ],
        child: const BaraedaManagerApp(),
      ),
    );
    await tester.pumpAndSettle();
    // 로그아웃은 내 정보 탭 맨 아래에만 있다(`Ruling 826`).
    await tester.tap(find.text('내 정보'));
    await tester.pumpAndSettle();
  }

  Finder dialogButton(String text) => find.descendant(
    of: find.byType(BaraedaDialog),
    matching: find.text(text),
  );

  testWidgets('로그아웃 버튼을 누르면 확인 대화상자가 뜨고, 취소하면 아무 일도 없다', (
    tester,
  ) async {
    final repository = _StubAuthRepository();
    await pump(tester, authRepository: repository);

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();

    expect(find.byType(BaraedaDialog), findsOneWidget);
    expect(repository.logoutCalls, 0);

    await tester.tap(dialogButton('닫기'));
    await tester.pumpAndSettle();

    expect(find.byType(BaraedaDialog), findsNothing);
    expect(repository.logoutCalls, 0);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('뒤로가기는 대화상자만 닫고 로그아웃도 화면 이탈도 없다', (tester) async {
    final repository = _StubAuthRepository();
    await pump(tester, authRepository: repository);

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(BaraedaDialog), findsNothing);
    expect(repository.logoutCalls, 0);
    expect(find.byType(MeScreen), findsOneWidget);
  });

  testWidgets('확인하면 로그아웃하고 로그인 화면으로 이동한다', (tester) async {
    final repository = _StubAuthRepository();
    await pump(tester, authRepository: repository);

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    await tester.tap(dialogButton('로그아웃'));
    await tester.pumpAndSettle();

    expect(repository.logoutCalls, 1);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('서버 호출이 실패해도 토큰을 지우고 로그인 화면으로 이동한다', (tester) async {
    final repository = _StubAuthRepository(fail: true);
    await pump(tester, authRepository: repository);

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    await tester.tap(dialogButton('로그아웃'));
    await tester.pumpAndSettle();

    expect(repository.logoutCalls, 1);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('운행 중인 회차가 있으면 확인 문구에 경고가 붙는다', (tester) async {
    await pump(
      tester,
      authRepository: _StubAuthRepository(),
      extraMovingRun: RunStatus.moving,
    );

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('운행 중에 로그아웃하면 명단·위치 송신이 멈춥니다'),
      findsOneWidget,
    );
  });

  testWidgets('운행 중인 회차가 없으면 경고 문구가 없다', (tester) async {
    await pump(tester, authRepository: _StubAuthRepository());

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('운행 중에 로그아웃하면 명단·위치 송신이 멈춥니다'),
      findsNothing,
    );
  });

  // M2-01(Ruling 388) — 로그아웃하면 미전송 대기열이 버려진다. 비어 있지 않을 때만 알린다.
  testWidgets('미전송 대기 요청이 있으면 확인 문구에 버려진다는 경고와 건수가 붙는다', (tester) async {
    await pump(tester, authRepository: _StubAuthRepository(), pendingCount: 2);

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();

    expect(find.textContaining('아직 보내지 못한 처리 2건은 버려집니다'), findsOneWidget);
    // 대기열을 먼저 볼 길이 맨 위에 있다(M8).
    expect(find.text('대기열 2건 먼저 보기'), findsOneWidget);
  });

  testWidgets('미전송 대기 요청이 없으면 버려진다는 경고가 없다', (tester) async {
    await pump(tester, authRepository: _StubAuthRepository());

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();

    expect(find.textContaining('버려집니다'), findsNothing);
  });
}
