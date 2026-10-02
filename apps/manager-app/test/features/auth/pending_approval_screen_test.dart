import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/app.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/features/auth/domain/auth_repository.dart';
import 'package:manager_app/features/auth/presentation/pending_approval_screen.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/home/presentation/home_screen.dart';

import '../../support/fake_token_storage.dart';

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
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
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
    expect(find.text('가입 승인을 기다리고 있습니다'), findsOneWidget);

    await tester.tap(find.text('상태 다시 확인'));
    await tester.pumpAndSettle();

    expect(repository.signupStatusCalls, 2);
    expect(find.text('가입이 거절되었습니다'), findsOneWidget);
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

  testWidgets('여전히 대기 중이면 대기 화면에 남는다', (tester) async {
    final repository = await pumpPending(tester);

    await tester.tap(find.text('상태 다시 확인'));
    await tester.pumpAndSettle();

    expect(repository.signupStatusCalls, 2);
    expect(find.byType(PendingApprovalScreen), findsOneWidget);
    expect(find.text('가입 승인을 기다리고 있습니다'), findsOneWidget);
  });

  testWidgets('다시 확인이 실패하면 다시 시도 안내를 보여준다', (tester) async {
    await pumpPending(tester, failFromSecondCall: true);

    await tester.tap(find.text('상태 다시 확인'));
    await tester.pumpAndSettle();

    expect(find.text('상태를 불러오지 못했습니다'), findsOneWidget);
    expect(find.byType(ManagerHomeScreen), findsNothing);
  });
}
