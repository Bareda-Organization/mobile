import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/app.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/app/router.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/features/auth/presentation/login_screen.dart';
import 'package:parent_app/features/auth/presentation/pending_approval_screen.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';
import 'package:parent_app/features/schedule/presentation/daily_change_screen.dart';
import 'package:parent_app/features/schedule/presentation/schedule_screen.dart';
import 'package:parent_app/features/schedule/presentation/weekly_address_screen.dart';

import '../support/fake_token_storage.dart';

/// `router.dart` 의 계정 상태 게이트(docs/archive/rounds/fe-phases-f2-f5.md §5.0 목표 7항 · `API_SPEC §1.4`)를
/// 직접 무는 시험 — 게이트 리뷰(`.claude/f3/gate-f2-flutter.md`)가 이
/// 조건을 지워도 기존 시험 10/10 이 그대로 통과하는 것을 확인한 자리다.
///
/// `role`·`status` provider 를 로그인 응답을 거치지 않고 직접
/// `overrideWith` 로 주입한다 — 이 시험의 관심사는 "로그인 응답을 provider
/// 로 옮기는 로직"(그건 `account_session.dart` 의 `applyRoleAndStatus` 가
/// 이미 검사됨)이 아니라 "그 provider 값을 보고 라우터가 어느 화면으로
/// 보내는가" 하나이기 때문이다.
///
/// `blocked` 상태는 여기서 다루지 않는다 — `AccountStatus` enum 자체에
/// `blocked` 이 없다(로그인이 실패로 끝나 role·status 가 아예 생기지
/// 않는다, `account_status.dart` 문서 주석 참고). 라우터의 redirect 로직도
/// `blockedAccount` 라우트를 "여기서 벗어나게 하지 않는다"로만 다뤄
/// 게이트 조건과 무관하다 — 대신 `login_screen.dart` 의 명시적 push 로
/// 검증 대상이 갈린다.
void main() {
  Future<void> pumpLoggedInAs(
    WidgetTester tester, {
    required AccountStatus status,
    UserRole role = UserRole.parent,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          currentUserRoleProvider.overrideWith((ref) => role),
          currentAccountStatusProvider.overrideWith((ref) => status),
        ],
        child: const BaraedaParentApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('pending 계정은 로그인 화면 대신 대기 화면으로 옮겨간다', (
    tester,
  ) async {
    await pumpLoggedInAs(tester, status: AccountStatus.pending);

    expect(find.byType(PendingApprovalScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('rejected 계정도 대기 화면(거절 안내)으로 옮겨간다', (tester) async {
    await pumpLoggedInAs(tester, status: AccountStatus.rejected);

    expect(find.byType(PendingApprovalScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('active 계정은 대기 화면에 갇히지 않고 홈으로 간다', (tester) async {
    await pumpLoggedInAs(tester, status: AccountStatus.active);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(PendingApprovalScreen), findsNothing);
  });

  // R52 `Ruling 874`① — 학생에게는 일정 탭이 없다. 학생용 일정 안내 화면은 지우고, 주소로 들어오면 홈으로 보낸다.
  for (final path in [
    AppRoutes.schedule,
    AppRoutes.weeklyAddress,
    AppRoutes.dailyChange,
  ]) {
    testWidgets('학생이 $path 로 들어와도 일정 화면이 아니라 홈이 보인다', (tester) async {
      await pumpLoggedInAs(
        tester,
        status: AccountStatus.active,
        role: UserRole.student,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(BaraedaParentApp)),
      );

      container.read(routerProvider).go(path);
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ScheduleScreen), findsNothing);
      expect(find.byType(WeeklyAddressScreen), findsNothing);
      expect(find.byType(DailyChangeScreen), findsNothing);
    });
  }

  testWidgets('학부모는 /schedule 로 일정 화면에 들어간다', (tester) async {
    await pumpLoggedInAs(tester, status: AccountStatus.active);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(BaraedaParentApp)),
    );

    container.read(routerProvider).go(AppRoutes.schedule);
    await tester.pumpAndSettle();

    expect(find.byType(ScheduleScreen), findsOneWidget);
  });
}
