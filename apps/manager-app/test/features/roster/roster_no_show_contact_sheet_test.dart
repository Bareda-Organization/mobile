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
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/roster/presentation/roster_screen.dart';

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

bool _chipEnabled(WidgetTester tester, String label) =>
    tester
        .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
        .onSelected !=
    null;

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
        child: const MaterialApp(home: RosterScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BaraedaButton, '연락 기록'));
    await tester.pumpAndSettle();
    return clock;
  }

  testWidgets('연락 기록 시트 제목은 사양 용어 "미승차" 를 쓴다 (R46, B2 #25)', (tester) async {
    await openSheet(tester, expiresAt: start.add(const Duration(minutes: 1)));

    expect(find.text('미승차 연락 기록'), findsOneWidget);
    expect(find.textContaining('미탑승'), findsNothing);
  });

  testWidgets('대기 시간 안에는 최종 판단 선택지가 꺼지고 남은 시간이 보인다', (tester) async {
    await openSheet(
      tester,
      expiresAt: start.add(const Duration(minutes: 2, seconds: 30)),
    );

    expect(find.textContaining('남은 시간 2분 30초'), findsOneWidget);
    expect(_chipEnabled(tester, '출발 확정'), isFalse);
    expect(_chipEnabled(tester, '재시도'), isFalse);
    expect(_chipEnabled(tester, '미정'), isTrue);
    expect(find.textContaining('3분'), findsNothing);
  });

  testWidgets('대기 시간이 끝나면 선택지가 열리고 남은 시간 문구가 사라진다', (tester) async {
    final clock = await openSheet(
      tester,
      expiresAt: start.add(const Duration(seconds: 30)),
    );
    expect(_chipEnabled(tester, '출발 확정'), isFalse);

    clock.current = start.add(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 1));

    expect(_chipEnabled(tester, '출발 확정'), isTrue);
    expect(_chipEnabled(tester, '재시도'), isTrue);
    expect(find.textContaining('남은 시간'), findsNothing);
  });

  testWidgets('만료 시각을 모르면 막지 않는다(서버가 최종 판정)', (tester) async {
    await openSheet(tester, expiresAt: null);

    expect(_chipEnabled(tester, '출발 확정'), isTrue);
    expect(find.textContaining('남은 시간'), findsNothing);
  });
}
