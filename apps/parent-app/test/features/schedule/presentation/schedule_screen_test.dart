import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/features/schedule/presentation/schedule_screen.dart';
import 'package:parent_app/features/schedule/presentation/widgets/change_request_panel.dart';
import 'package:parent_app/features/schedule/presentation/widgets/weekly_address_editor.dart';

/// 게이트 판정 🔴-2 — 학생 role 로는 등하원 일정 편집 진입점
/// (`WeeklyAddressEditor`·`ChangeRequestPanel`)이 노출되지 않는다는 것을
/// 고정하는 화면 단위 테스트. `canEdit` 삼항을 `true` 로 심는 변형과
/// `?? false` 를 `?? true` 로 심는 변형(role 판정 미상 시 개방) 둘 다
/// 이 테스트로 잡혀야 한다.
Future<void> _pumpWith(WidgetTester tester, {UserRole? role}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [currentUserRoleProvider.overrideWith((ref) => role)],
      child: const MaterialApp(home: ScheduleScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('학생 role 로는 주소 편집·변경 신청 진입점이 보이지 않는다', (tester) async {
    await _pumpWith(tester, role: UserRole.student);

    expect(find.byType(WeeklyAddressEditor), findsNothing);
    expect(find.byType(ChangeRequestPanel), findsNothing);
    expect(find.text('등하원 일정은 부모님 계정에서 관리합니다'), findsOneWidget);
  });

  testWidgets('role 판정이 아직 없으면(null) 편집 화면 대신 안내만 보인다 (기본값은 닫힘)', (
    tester,
  ) async {
    await _pumpWith(tester);

    expect(find.byType(WeeklyAddressEditor), findsNothing);
    expect(find.byType(ChangeRequestPanel), findsNothing);
    expect(find.text('등하원 일정은 부모님 계정에서 관리합니다'), findsOneWidget);
  });
}
