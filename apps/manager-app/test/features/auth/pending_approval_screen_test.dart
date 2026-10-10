import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart' show DropdownButtonFormField, TextField;
import 'package:flutter/widgets.dart' show AppLifecycleState;
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
import 'package:manager_app/features/auth/presentation/pending_approval_screen.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/domain/manager_run_repository.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/home/presentation/home_screen.dart';

import '../../support/fake_academy_contact_store.dart';
import '../../support/fake_last_session_store.dart';
import '../../support/fake_token_storage.dart';

class _NoRuns implements ManagerRunRepository {
  @override
  Future<List<ManagerRun>> fetchRuns({DateTime? date}) async => const [];
}

/// R33 M3 — 승인 대기 화면은 상태를 한 번만 조회해, 관리자가 승인·거절해도 앱을 껐다 켜야 알 수 있었다.
/// [상태 다시 확인] 은 다시 조회해 화면에 반영하고, 승인(`active`)이면 홈으로 보낸다(학부모 앱 R32 P9 와 같은 동작).
class _StubAuthRepository implements AuthRepository {
  /// `signupStatus` 호출 횟수 — [다시 확인] 이 실제로 서버를 다시 부르는지 본다.
  int signupStatusCalls = 0;

  /// 두 번째 조회부터 이 상태로 응답한다(관리자가 그 사이에 승인·거절한 상황).
  AccountStatus? statusFromSecondCall;

  /// 두 번째 조회부터 실패로 응답한다.
  bool failFromSecondCall = false;

  /// 학원이 대표 연락처를 등록하지 않은 응답
  /// (`academy_contact: null` — API_SPEC §2.3, Ruling 781).
  bool academyContactMissing = false;

  /// `reapply` 로 보낸 학원 id 들 — 확인 창을 취소하면 비어 있어야 한다.
  final reappliedAcademyIds = <String>[];

  /// 승인 뒤 `/me` — 활성 기사.
  @override
  Future<MeResponse> me() async => const MeResponse(
    accountId: 'a-1',
    loginId: 'id',
    name: '이름',
    phone: '010',
    role: AccountRole.driver,
    status: AccountStatus.active,
  );

  @override
  Future<List<AcademySummary>> searchAcademies(String query) async => [
    const AcademySummary(
      id: 'academy-7',
      name: '새학원',
      region: '부천',
      code: 'B-007',
    ),
  ];

  @override
  Future<ReapplyResponse> reapply({required String academyId}) async {
    reappliedAcademyIds.add(academyId);
    return ReapplyResponse(
      status: AccountStatus.pending,
      requestedAt: DateTime(2026, 9),
    );
  }

  @override
  Future<SignupStatusResponse> signupStatus() async {
    signupStatusCalls++;
    if (academyContactMissing) {
      // 서버가 보내는 JSON 그대로 읽는다 — 파싱이 null 을 못 받으면 여기서 던진다.
      return SignupStatusResponse.fromJson({
        'status': 'pending',
        'academy': {'name': '바래다학원', 'region': '서울', 'code': 'A-001'},
        'requested_at': '2026-09-01T00:00:00Z',
        'academy_contact': null,
      });
    }
    if (signupStatusCalls > 1 && failFromSecondCall) {
      // Failure 는 Exception/Error 를 상속하지 않는다(다른 시험의 같은 패턴).
      // ignore: only_throw_errors
      throw const NetworkFailure();
    }
    return SignupStatusResponse(
      status: signupStatusCalls > 1
          ? statusFromSecondCall ?? AccountStatus.pending
          : AccountStatus.pending,
      academyName: '바래다학원',
      academyRegion: '서울',
      academyCode: 'A-001',
      requestedAt: DateTime(2026, 9),
      academyContact: '02-000-0000',
      rejectReason:
          signupStatusCalls > 1 &&
              statusFromSecondCall == AccountStatus.rejected
          ? '학원의 기사 명단에서 이름을 찾을 수 없어요.'
          : null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  /// 기기가 기억한 마지막 역할 — 승인 대기로 로그인했으면 비어 있다.
  late FakeLastSessionStore lastSession;

  setUp(() => lastSession = FakeLastSessionStore());

  /// 실제 라우터로 띄운다 — 승인되면 홈으로 가는지까지 본다.
  Future<_StubAuthRepository> pumpPending(
    WidgetTester tester, {
    AccountStatus? statusFromSecondCall,
    bool failFromSecondCall = false,
    bool academyContactMissing = false,
  }) async {
    final repository = _StubAuthRepository()
      ..statusFromSecondCall = statusFromSecondCall
      ..failFromSecondCall = failFromSecondCall
      ..academyContactMissing = academyContactMissing;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
          currentAccountStatusProvider.overrideWith(
            (ref) => AccountStatus.pending,
          ),
          authRepositoryProvider.overrideWithValue(repository),
          lastSessionStoreProvider.overrideWithValue(lastSession),
          academyContactStoreProvider.overrideWithValue(
            FakeAcademyContactStore(),
          ),
          managerRunRepositoryProvider.overrideWithValue(_NoRuns()),
          todayRunsProvider.overrideWith((ref) async => []),
        ],
        child: const BaraedaManagerApp(),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  // BR-301(Ruling 781) — 학원이 연락처를 등록하지 않아 academy_contact 가 null 이어도 화면이 뜬다.
  testWidgets('학원 문의처가 null 이면 대체 문구를 보여준다', (tester) async {
    await pumpPending(tester, academyContactMissing: true);

    expect(find.byType(PendingApprovalScreen), findsOneWidget);
    expect(find.text('등록된 문의처 없음'), findsOneWidget);
  });

  testWidgets('학원 문의처가 있으면 그 값을 보여주고 대체 문구는 없다', (tester) async {
    await pumpPending(tester);

    expect(find.text('02-000-0000'), findsOneWidget);
    expect(find.text('등록된 문의처 없음'), findsNothing);
  });

  testWidgets('대기 화면에 [상태 다시 확인] 이 있다', (tester) async {
    await pumpPending(tester);

    expect(find.byType(PendingApprovalScreen), findsOneWidget);
    expect(find.text('상태 다시 확인'), findsOneWidget);
  });

  testWidgets('[상태 다시 확인] 을 누르면 다시 조회해 거절 상태를 화면에 반영한다', (tester) async {
    final repository = await pumpPending(
      tester,
      statusFromSecondCall: AccountStatus.rejected,
    );
    expect(find.text('가입 승인을 기다리고 있어요'), findsOneWidget);

    await tester.tap(find.text('상태 다시 확인'));
    await tester.pumpAndSettle();

    expect(repository.signupStatusCalls, 2);
    expect(find.text('가입이 거절됐어요'), findsOneWidget);
  });

  testWidgets('다시 확인했더니 승인됐으면 홈으로 간다', (tester) async {
    final repository = await pumpPending(
      tester,
      statusFromSecondCall: AccountStatus.active,
    );

    await tester.tap(find.text('상태 다시 확인'));
    await tester.pumpAndSettle();

    expect(repository.signupStatusCalls, 2);
    expect(find.byType(ManagerHomeScreen), findsOneWidget);
    expect(find.byType(PendingApprovalScreen), findsNothing);
  });

  // 승인 대기로 로그인하면 저장 역할이 비어 있다 — 승인을 확인한 순간 /me 를 적용해야 이후 통신 두절에도 오프라인 입장이 된다.
  testWidgets('[상태 다시 확인] 으로 승인을 확인하면 오프라인 입장용 역할이 기기에 남는다', (tester) async {
    await pumpPending(tester, statusFromSecondCall: AccountStatus.active);
    expect(lastSession.role, isNull);

    await tester.tap(find.text('상태 다시 확인'));
    await tester.pumpAndSettle();

    expect(lastSession.role, AccountRole.driver);
  });

  testWidgets('주기 확인으로 승인을 확인해도 오프라인 입장용 역할이 기기에 남는다', (tester) async {
    await pumpPending(tester, statusFromSecondCall: AccountStatus.active);

    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    expect(lastSession.role, AccountRole.driver);
  });

  testWidgets('여전히 대기 중이면 대기 화면에 남는다', (tester) async {
    final repository = await pumpPending(tester);

    await tester.tap(find.text('상태 다시 확인'));
    await tester.pumpAndSettle();

    expect(repository.signupStatusCalls, 2);
    expect(find.byType(PendingApprovalScreen), findsOneWidget);
    expect(find.text('가입 승인을 기다리고 있어요'), findsOneWidget);
  });

  testWidgets('다시 확인이 실패하면 다시 시도 안내를 보여준다', (tester) async {
    await pumpPending(tester, failFromSecondCall: true);

    await tester.tap(find.text('상태 다시 확인'));
    await tester.pumpAndSettle();

    expect(find.text('상태를 불러오지 못했습니다'), findsOneWidget);
    expect(find.byType(ManagerHomeScreen), findsNothing);
  });

  // R52 M6 — 승인은 관계자가 따로 하므로 앱이 돌아오면 바로 다시 보고, 자동 확인이 실패해도 오류 화면으로 바꾸지
  // 않는다(학부모 앱 `VisiblePoller` 와 같은 동작 · frontend `Ruling 473`).
  group('자동 확인 (R52 M6)', () {
    Future<void> backgroundThenResume(WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    }

    testWidgets('앱이 백그라운드에서 돌아오면 간격을 기다리지 않고 바로 다시 확인한다', (tester) async {
      final repository = await pumpPending(
        tester,
        statusFromSecondCall: AccountStatus.rejected,
      );
      expect(repository.signupStatusCalls, 1);

      await backgroundThenResume(tester);

      expect(repository.signupStatusCalls, 2);
      expect(find.text('가입이 거절됐어요'), findsOneWidget);
    });

    testWidgets('백그라운드에 있는 동안에는 주기 확인을 건너뛴다', (tester) async {
      final repository = await pumpPending(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 65));

      expect(repository.signupStatusCalls, 1);
    });

    testWidgets('주기 확인이 실패해도 오류 화면 대신 보던 대기 화면을 그대로 둔다', (tester) async {
      final repository = await pumpPending(tester, failFromSecondCall: true);

      await tester.pump(const Duration(seconds: 31));
      await tester.pump();

      expect(repository.signupStatusCalls, 2);
      expect(find.text('상태를 불러오지 못했습니다'), findsNothing);
      expect(find.text('가입 승인을 기다리고 있어요'), findsOneWidget);
    });

    testWidgets('주기 확인에서 승인됐으면 홈으로 간다', (tester) async {
      await pumpPending(tester, statusFromSecondCall: AccountStatus.active);

      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();

      expect(find.byType(ManagerHomeScreen), findsOneWidget);
    });
  });

  // 시안 `pending--rejected` — 거절 사유 · 신청 정보 표 · 다른 학원으로 다시 신청.
  group('거절 화면 (시안 pending--rejected)', () {
    Future<_StubAuthRepository> pumpRejected(WidgetTester tester) async {
      final repository = await pumpPending(
        tester,
        statusFromSecondCall: AccountStatus.rejected,
      );
      await tester.tap(find.text('상태 다시 확인'));
      await tester.pumpAndSettle();
      return repository;
    }

    /// 학원을 검색해 고른 뒤 [이 학원으로 재신청] 을 누른다.
    Future<void> pickAcademyAndTapReapply(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField), '새');
      await tester.ensureVisible(find.text('검색하기'));
      await tester.tap(find.text('검색하기'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('새학원 · 부천 · B-007').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('이 학원으로 재신청'));
      await tester.pumpAndSettle();
    }

    testWidgets('사유를 띠 본문에 싣고 신청 학원 · 상태 · 문의처 표를 보여준다', (tester) async {
      await pumpRejected(tester);

      expect(find.text('사유 · 학원의 기사 명단에서 이름을 찾을 수 없어요.'), findsOneWidget);
      for (final label in ['신청 학원', '신청 일시', '현재 상태', '학원 문의처']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('바래다학원'), findsOneWidget);
      expect(find.text('거절됨'), findsOneWidget);
      expect(find.text('02-000-0000'), findsOneWidget);
      expect(find.widgetWithText(BaraedaButton, '전화'), findsOneWidget);
    });

    testWidgets('다른 학원으로 다시 신청하는 칸이 처음부터 있고 학원을 고르기 전엔 재신청이 꺼진다', (
      tester,
    ) async {
      await pumpRejected(tester);

      expect(find.text('다른 학원으로 다시 신청'), findsOneWidget);
      final button = tester.widget<BaraedaButton>(
        find.widgetWithText(BaraedaButton, '이 학원으로 재신청'),
      );
      expect(button.onPressed, isNull);
      expect(find.text('다시 신청할 학원을 고르면 눌러요'), findsOneWidget);
      expect(find.widgetWithText(BaraedaButton, '로그아웃'), findsOneWidget);
    });

    // A8 — 신청한 뒤에는 되돌릴 수 없어 확인 창 한 단계를 거친다.
    testWidgets('재신청은 확인 창에서 취소하면 보내지 않는다', (tester) async {
      final repository = await pumpRejected(tester);

      await pickAcademyAndTapReapply(tester);
      expect(find.text('가입을 다시 신청할까요?'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(repository.reappliedAcademyIds, isEmpty);
    });

    testWidgets('재신청은 확인 창에서 [다시 신청] 을 눌러야 보낸다', (tester) async {
      final repository = await pumpRejected(tester);

      await pickAcademyAndTapReapply(tester);
      await tester.tap(find.text('다시 신청'));
      await tester.pumpAndSettle();

      expect(repository.reappliedAcademyIds, ['academy-7']);
    });
  });
}
