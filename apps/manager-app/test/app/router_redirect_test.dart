import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/app.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/features/auth/presentation/login_screen.dart';
import 'package:manager_app/features/auth/presentation/pending_approval_screen.dart';
import 'package:manager_app/features/home/presentation/home_screen.dart';

import '../support/fake_token_storage.dart';

/// `router.dart` 의 계정 상태 게이트(§5.0 목표 7항 · `API_SPEC §1.4`)를
/// 직접 무는 시험 — parent-app 의 같은 이름 파일과 동일한 목적이다.
/// 이 앱의 `router.dart` redirect 콜백은 parent-app 과 파일 대조로
/// 바이트 단위까지 동일함을 확인했으나(임포트·`routes` 목록만 다름),
/// 그 근거만으로 이 앱의 검사를 생략하지 않는다 — 여기서도 직접 심고
/// 직접 되돌려 확인한다.
///
/// `role`·`status` provider 를 로그인 응답을 거치지 않고 직접
/// `overrideWith` 로 주입한다 — 이 시험의 관심사는 "로그인 응답을 provider
/// 로 옮기는 로직"이 아니라 "그 provider 값을 보고 라우터가 어느 화면으로
/// 보내는가" 하나이기 때문이다.
///
/// `blocked` 상태는 여기서 다루지 않는다 — `AccountStatus` enum 자체에
/// `blocked` 이 없다(로그인이 실패로 끝나 role·status 가 아예 생기지
/// 않는다, `account_status.dart` 문서 주석 참고).
void main() {
  Future<void> pumpLoggedInAs(
    WidgetTester tester, {
    required AccountStatus status,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          currentUserRoleProvider.overrideWith((ref) => UserRole.driver),
          currentAccountStatusProvider.overrideWith((ref) => status),
        ],
        child: const BaraedaManagerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('pending 계정은 로그인 화면 대신 대기 화면으로 옮겨간다', (
    tester,
  ) async {
    await pumpLoggedInAs(tester, status: AccountStatus.pending);

    expect(find.byType(PendingApprovalScreen), findsOneWidget);
    expect(find.byType(ManagerHomeScreen), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('rejected 계정도 대기 화면(거절 안내)으로 옮겨간다', (tester) async {
    await pumpLoggedInAs(tester, status: AccountStatus.rejected);

    expect(find.byType(PendingApprovalScreen), findsOneWidget);
    expect(find.byType(ManagerHomeScreen), findsNothing);
  });

  testWidgets('active 계정은 대기 화면에 갇히지 않고 홈으로 간다', (tester) async {
    await pumpLoggedInAs(tester, status: AccountStatus.active);

    expect(find.byType(ManagerHomeScreen), findsOneWidget);
    expect(find.byType(PendingApprovalScreen), findsNothing);
  });
}
