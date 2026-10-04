import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/no_show_screen.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import '../../support/manager_run_fixture.dart';

/// R32 M12 — 미승차 연락 시트의 최종 판단은 대기 시간이 끝난 뒤에만 고를 수 있다. 대기 시간은
/// 학원 설정값(A-17, 기본 3분)이라 화면에 "3분" 을 박지 않고, 명단 응답의 `no_show_case.expires_at`
/// (서버가 학원 설정으로 계산)을 그대로 쓴다.
class _MutableClock implements Clock {
  new(this.current);

  DateTime current;

  @override
  DateTime now() => current;
}

class _NeverResolvingTokenStorage extends TokenStorage {
  new()
    : super(
        accessTokenKey: 'test_access_token',
        refreshTokenKey: 'test_refresh_token',
      );

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;
}

RosterResponse _roster({DateTime? expiresAt}) => RosterResponse(
  runId: 'run-1',
  busNo: '3호차',
  direction: RunDirection.toAcademy,
  counts: const RosterCounts(boarded: 0, waiting: 0, noShow: 1, absentN: 0),
  stops: [
    RosterStop(
      stopId: 'st1',
      seq: 1,
      name: 'A정류장',
      students: [
        RosterStudent(
          riderId: 'r1',
          studentId: 's1',
          name: '김바래',
          photoUrl: null,
          guardianPhone: null,
          canGoAlone: false,
          status: RiderStatus.noShow,
          noShowCase: expiresAt == null
              ? null
              : NoShowCase(
                  caseId: 'c1',
                  startedAt: expiresAt.subtract(const Duration(minutes: 5)),
                  expiresAt: expiresAt,
                ),
        ),
      ],
    ),
  ],
);

/// 최종 판단 선택지가 눌리는가 — 대기 시간 안에는 `미정` 밖을 눌러도 선택이 바뀌지 않는다.
/// 구간 선택은 칸마다 켜짐 여부를 갖지 않으므로 눌러 본 뒤 선택된 칸이 바뀌었는지로 판정한다.
Future<bool> _selectable(WidgetTester tester, String label) async {
  final control = find.byWidgetPredicate(
    (widget) =>
        widget is BaraedaSegmentedControl &&
        widget.options.any((o) => o.label == label),
  );
  await tester.tap(find.descendant(of: control, matching: find.text(label)));
  await tester.pump();
  return tester.widget<BaraedaSegmentedControl>(control).value ==
      tester
          .widget<BaraedaSegmentedControl>(control)
          .options
          .firstWhere((o) => o.label == label)
          .value;
}

void main() {
  final start = DateTime(2026, 9, 30, 8);

  Future<_MutableClock> openSheet(
    WidgetTester tester, {
    required DateTime? expiresAt,
  }) async {
    final clock = _MutableClock(start);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(clock),
          tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
          selectedRunIdProvider.overrideWith((ref) => 'run-1'),
          currentUserRoleProvider.overrideWith((ref) => UserRole.escort),
          todayRunsProvider.overrideWith((ref) async => [managerRunFixture()]),
          rosterProvider.overrideWith(
            (ref) async => _roster(expiresAt: expiresAt),
          ),
        ],
        child: const MaterialApp(home: NoShowScreen(riderId: 'r1')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BaraedaButton, '연락 기록 남기기'));
    await tester.pumpAndSettle();
    return clock;
  }

  testWidgets('연락 기록 시트 제목은 사양 용어 "미승차" 를 쓴다 (R46, B2 #25)', (tester) async {
    await openSheet(tester, expiresAt: start.add(const Duration(minutes: 1)));

    expect(find.text('연락 기록'), findsWidgets);
    expect(find.text('미승차 연락'), findsOneWidget);
    expect(find.textContaining('미탑승'), findsNothing);
  });

  testWidgets('대기 시간 안에는 최종 판단 선택지가 꺼지고 남은 시간이 보인다', (tester) async {
    await openSheet(
      tester,
      expiresAt: start.add(const Duration(minutes: 2, seconds: 30)),
    );

    expect(find.textContaining('2분 30초 남음'), findsOneWidget);
    expect(await _selectable(tester, '출발 확정'), isFalse);
    expect(await _selectable(tester, '재시도'), isFalse);
    expect(await _selectable(tester, '미정'), isTrue);
  });

  testWidgets('대기 시간이 끝나면 선택지가 열리고 남은 시간 문구가 사라진다', (tester) async {
    final clock = await openSheet(
      tester,
      expiresAt: start.add(const Duration(seconds: 30)),
    );
    expect(await _selectable(tester, '출발 확정'), isFalse);

    clock.current = start.add(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 1));

    expect(await _selectable(tester, '출발 확정'), isTrue);
    expect(await _selectable(tester, '재시도'), isTrue);
    expect(find.textContaining('남음'), findsNothing);
  });

  testWidgets('이미 대기가 끝난 케이스는 처음부터 막지 않는다', (tester) async {
    await openSheet(
      tester,
      expiresAt: start.subtract(const Duration(minutes: 1)),
    );

    expect(await _selectable(tester, '출발 확정'), isTrue);
    expect(find.textContaining('남음'), findsNothing);
  });
}
