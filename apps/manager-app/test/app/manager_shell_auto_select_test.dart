import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/app.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/account_session.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/me_provider.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/home/data/models/manager_run.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';

import '../support/fake_notification_repository.dart';
import '../support/fake_token_storage.dart';
import '../support/manager_run_fixture.dart';

/// R52 H1(수정 라운드 1) — 고른 회차가 끝났고 큰 카드(focus)가 다른 회차를 가리키면 쉘이 선택을 갈아탄다.
/// 동승자의 명단 탭 · 거기서 여는 지연 알림 · 예외 보고는 모두 선택 회차([selectedRunIdProvider])를 읽으므로
/// 쉘의 선택이 다음 회차를 가리키면 셋 다 따라간다. 쉘이 맨 위 화면이 아닐 때(운행 종료 · 보고 화면이 위에 있을 때)는
/// 바꾸지 않는다.
/// 운행 채널(WebSocket)이 연결을 시작하지 못하게 토큰 읽기를 멈춰 둔다.
class _NeverResolvingTokenStorage extends FakeTokenStorage {
  new();

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;
}

final _runs = StateProvider<List<ManagerRun>>((ref) => const []);

void main() {
  ManagerRun finishedA() => managerRunFixture(
    runId: 'run-A',
    busNo: '1호차',
    status: RunStatus.finished,
    departTime: DateTime(2026, 10, 3, 8),
  );
  ManagerRun confirmedA() => managerRunFixture(
    runId: 'run-A',
    busNo: '1호차',
    departTime: DateTime(2026, 10, 3, 8),
  );
  ManagerRun confirmedB() => managerRunFixture(
    runId: 'run-B',
    busNo: '2호차',
    departTime: DateTime(2026, 10, 3, 12),
  );

  Future<ProviderContainer> pump(
    WidgetTester tester,
    UserRole role,
    List<ManagerRun> initial,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(_NeverResolvingTokenStorage()),
          currentUserRoleProvider.overrideWith((ref) => role),
          currentAccountStatusProvider.overrideWith(
            (ref) => AccountStatus.active,
          ),
          meProvider.overrideWith((ref) async => throw StateError('내 정보 미사용')),
          _runs.overrideWith((ref) => initial),
          todayRunsProvider.overrideWith((ref) => ref.watch(_runs)),
          rosterProvider.overrideWith(
            (ref) async => const RosterResponse(
              runId: 'run-A',
              busNo: '1호차',
              direction: RunDirection.toAcademy,
              counts: RosterCounts(
                boarded: 0,
                waiting: 0,
                noShow: 0,
                absentN: 0,
              ),
              stops: [],
            ),
          ),
          selectedRunIdProvider.overrideWith((ref) => 'run-A'),
          notificationRepositoryProvider.overrideWithValue(
            FakeNotificationRepository(const []),
          ),
        ],
        child: const BaraedaManagerApp(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(BaraedaTabBar)),
    );
  }

  testWidgets('동승자: 앞 회차 A 가 끝나고 B 가 확정이면 명단 · 지연 알림 · 예외 보고가 읽는 선택이 B 로 바뀐다', (
    tester,
  ) async {
    final container = await pump(tester, UserRole.escort, [
      finishedA(),
      confirmedB(),
    ]);

    expect(container.read(selectedRunIdProvider), 'run-B');
    expect(container.read(selectedManagerRunProvider)?.busNo, '2호차');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 쉘 위에 다른 화면이 떠 있는 동안 앞 회차가 끝난다. 옆 화면(페이지)은 Riverpod 이 구독을 멈춰 두지만 대화상자는
  // 아래 쉘이 계속 다시 그려지므로, 두 경우 모두 쉘이 맨 위 화면일 때만 갈아타야 한다.
  for (final (label, open) in <(String, Future<void> Function(BuildContext))>[
    (
      '종료 화면(페이지)',
      (context) => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('운행 종료 화면')),
        ),
      ),
    ),
    (
      '대화상자',
      (context) => showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('운행 종료 화면')),
      ),
    ),
  ]) {
    testWidgets('$label 가 쉘 위에 떠 있는 동안에는 선택을 바꾸지 않고, 닫으면 갈아탄다', (tester) async {
      final container = await pump(tester, UserRole.driver, [
        confirmedA(),
        confirmedB(),
      ]);
      expect(container.read(selectedRunIdProvider), 'run-A');

      final context = tester.element(find.byType(BaraedaTabBar));
      unawaited(open(context));
      await tester.pumpAndSettle();

      // 위 화면이 떠 있는 동안 A 가 끝난다.
      container.read(_runs.notifier).state = [finishedA(), confirmedB()];
      await tester.pumpAndSettle();
      expect(find.text('운행 종료 화면'), findsOneWidget);
      expect(container.read(selectedRunIdProvider), 'run-A');

      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      expect(container.read(selectedRunIdProvider), 'run-B');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
