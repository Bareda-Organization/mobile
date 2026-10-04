import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/role_policy.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/change_requests/presentation/change_request_providers.dart';
import 'package:parent_app/core/routes/presentation/route_providers.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';
import 'package:parent_app/features/route/presentation/route_detail_screen.dart';
import '../support/no_bus_position.dart';

/// N-09(BR-212) — 퇴원한 학생 본인 계정의 회차·노선 조회는 `404 STUDENT_NOT_FOUND` 다.
/// 앱은 죽지 않고, 다시 해도 같은 결과라는 것을 알려야 한다(막연한 "불러오지 못했습니다" + [다시 시도] 가 아니라).
const _withdrawn = Failure.api(
  statusCode: 404,
  code: 'STUDENT_NOT_FOUND',
  message: '학생을 찾을 수 없습니다',
);

Future<void> _pumpStudent(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
          noBusPositionOverride,
        roleCapabilitiesProvider.overrideWithValue(
          RoleCapabilities.of(UserRole.student),
        ),
        myStudentIdProvider.overrideWith((ref) async => 's-1'),
        runsForStudentProvider.overrideWith(
          // Failure 는 Exception/Error 를 상속하지 않는다 — 리포지토리가 던지는 형태 그대로.
          // ignore: only_throw_errors
          (ref, id) async => throw _withdrawn,
        ),
        routeDetailProvider.overrideWith(
          // 위와 같은 이유.
          // ignore: only_throw_errors
          (ref, id) async => throw _withdrawn,
        ),
        changeRequestsProvider.overrideWith(
          (ref, id) async =>
              const ChangeRequestPage(items: [], pendingCount: 0),
        ),
      ],
      child: MaterialApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('홈 — 퇴원 학생의 회차 조회 404 는 퇴원 안내로 보이고 다시 시도는 없다', (tester) async {
    await _pumpStudent(tester, const HomeScreen());

    expect(tester.takeException(), isNull);
    expect(find.textContaining('퇴원'), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);
  });

  testWidgets('노선 — 퇴원 학생의 노선 조회 404 는 퇴원 안내로 보인다', (tester) async {
    await _pumpStudent(tester, const RouteDetailScreen());

    expect(tester.takeException(), isNull);
    expect(find.textContaining('퇴원'), findsOneWidget);
  });
}
