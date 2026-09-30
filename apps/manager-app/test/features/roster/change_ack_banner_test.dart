import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';
import 'package:manager_app/features/roster/data/models/ack_changes_result.dart';
import 'package:manager_app/features/roster/domain/roster_repository.dart';
import 'package:manager_app/features/roster/presentation/widgets/change_ack_banner.dart';

class _AckOnlyRosterRepository implements RosterRepository {
  @override
  Future<AckChangesResult> ackChanges({required String runId}) async =>
      AckChangesResult(ackedAt: DateTime(2026, 9, 30, 8));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// F06-08 — 한 번 확인하면 그 화면이 떠 있는 동안 두 번째 노선 변경의 띠가 뜨지 않았다.
void main() {
  testWidgets('확인한 뒤 다음 변경으로 ack_required 가 다시 켜지면 띠가 다시 뜬다', (tester) async {
    final ackRequired = ValueNotifier<bool>(true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rosterRepositoryProvider.overrideWithValue(
            _AckOnlyRosterRepository(),
          ),
          todayRunsProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: ackRequired,
              builder: (_, value, _) =>
                  ChangeAckBanner(runId: 'run-1', ackRequired: value),
            ),
          ),
        ),
      ),
    );
    expect(find.text('변경 목록 확인'), findsOneWidget);

    await tester.tap(find.text('변경 목록 확인'));
    await tester.pumpAndSettle();
    expect(find.text('변경 목록 확인'), findsNothing, reason: '확인 직후에는 숨는다');

    // 서버가 목록을 다시 받아 ack_required=false 로 돌려준다.
    ackRequired.value = false;
    await tester.pump();
    // 관계자가 노선을 또 바꿨다 — ack_required 가 다시 true.
    ackRequired.value = true;
    await tester.pump();

    expect(find.text('변경 목록 확인'), findsOneWidget);
  });
}
