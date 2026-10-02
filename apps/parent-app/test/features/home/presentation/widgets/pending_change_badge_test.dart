import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';
import 'package:parent_app/core/change_requests/domain/change_request_repository.dart';
import 'package:parent_app/features/home/presentation/widgets/pending_change_badge.dart';

/// P-06 "홈에 처리 대기 건수 배지" 가 §3.9 `pending_count` 값을 실제로
/// 반영하는지 확인한다 — 0이면 아무것도 안 보이고, 0보다 크면 그 숫자를
/// 보여준다.
class _FixedChangeRequestRepository implements ChangeRequestRepository {
  new(this.pendingCount);

  final int pendingCount;

  @override
  Future<ChangeRequestCreateResult> createChangeRequest(
    String studentId, {
    required ChangeRequestType type,
    required String runId,
    String? newAddress,
    String? reason,
  }) => throw UnimplementedError();

  @override
  Future<ChangeRequestPage> getChangeRequests(String studentId) async =>
      ChangeRequestPage(items: const [], pendingCount: pendingCount);
}

Future<void> _pumpWith(WidgetTester tester, int pendingCount) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        changeRequestRepositoryProvider.overrideWithValue(
          _FixedChangeRequestRepository(pendingCount),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: PendingChangeBadge(studentId: 's-1')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('처리 대기가 0건이면 배지를 보여주지 않는다', (tester) async {
    await _pumpWith(tester, 0);

    expect(find.byType(PendingChangeBadge), findsOneWidget);
    expect(find.byType(BaraedaBadge), findsNothing);
  });

  testWidgets('처리 대기가 2건이면 건수를 배지로 보여준다', (tester) async {
    await _pumpWith(tester, 2);

    expect(find.text('처리 대기 · 2'), findsOneWidget);
  });

  // R32 P15 — 화면 읽기 프로그램은 배지를 "처리 대기 · 2" 로 읽어 건수인지 알기 어려웠다.
  testWidgets('P15 배지는 화면 읽기용 설명 "처리 대기 2건" 을 가진다', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpWith(tester, 2);

    expect(find.bySemanticsLabel('처리 대기 2건'), findsOneWidget);
    handle.dispose();
  });
}
