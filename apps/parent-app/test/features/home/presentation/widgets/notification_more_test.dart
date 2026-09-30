import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/features/home/domain/notification_item.dart';
import 'package:parent_app/features/home/domain/notification_repository.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';

final _sentAt = DateTime(2026, 9, 21, 8, 30);

NotificationItem _item(String id) => NotificationItem(
  notificationId: id,
  type: 'signup_decided',
  title: '알림 $id',
  body: '본문',
  sentAt: _sentAt,
  popup: false,
  studentName: '김영희',
);

/// 요청받은 `size` 를 기록하고, 그 크기만큼(최대 45건) 돌려주는 가짜.
class _PagedRepository implements NotificationRepository {
  _PagedRepository({this.unread = 0, this.failMarkRead = false});

  final int unread;
  final bool failMarkRead;
  final sizes = <int>[];

  @override
  Future<NotificationPage> getNotifications({
    int page = 0,
    int size = 20,
  }) async {
    sizes.add(size);
    final count = size < 45 ? size : 45;
    return NotificationPage(
      items: [for (var i = 0; i < count; i++) _item('n-$i')],
      page: page,
      size: size,
      totalCount: 45,
      hasNext: size < 45,
      unreadCount: unread,
    );
  }

  @override
  Future<void> markRead(String notificationId) async {
    if (failMarkRead) throw const Failure.network();
  }
}

/// F05-08 · F05-13 — 알림은 첫 20건에서 끝나지 않고, 미읽음 건수가 보이며, 읽음 처리 실패가 예외로 새지 않는다.
void main() {
  Future<_PagedRepository> pumpHome(
    WidgetTester tester, {
    int unread = 0,
    bool failMarkRead = false,
  }) async {
    final repository = _PagedRepository(
      unread: unread,
      failMarkRead: failMarkRead,
    );
    tester.view.physicalSize = const Size(800, 12000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myStudentIdProvider.overrideWith((ref) async => 's-1'),
          runsForStudentProvider.overrideWith(
            (ref, studentId) async => const <StudentRun>[],
          ),
          notificationRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('F05-08 다음 알림이 있으면 [더 보기] 가 있고 누르면 더 많이 받는다', (tester) async {
    final repository = await pumpHome(tester);
    expect(find.text('알림 n-19'), findsOneWidget);
    expect(find.text('알림 n-20'), findsNothing);

    await tester.tap(find.text('더 보기'));
    await tester.pumpAndSettle();

    expect(repository.sizes.last, 40);
    expect(find.text('알림 n-39'), findsOneWidget);
  });

  testWidgets('F05-08 마지막 페이지에서는 [더 보기] 가 없다', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('더 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('더 보기'));
    await tester.pumpAndSettle();

    expect(find.text('알림 n-44'), findsOneWidget);
    expect(find.text('더 보기'), findsNothing);
  });

  testWidgets('F05-08 안 읽은 알림 건수를 머리말에 보여준다', (tester) async {
    await pumpHome(tester, unread: 3);

    expect(find.text('안 읽음 · 3'), findsOneWidget);
  });

  testWidgets('F05-08 안 읽은 알림이 없으면 건수 표시가 없다', (tester) async {
    await pumpHome(tester);

    expect(find.textContaining('안 읽음'), findsNothing);
  });

  testWidgets('F05-13 읽음 처리가 실패해도 예외가 새지 않고 안내를 띄운다', (tester) async {
    await pumpHome(tester, failMarkRead: true);

    await tester.tap(find.text('알림 n-0'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('네트워크 상태를 확인해 주세요'), findsOneWidget);
  });
}
