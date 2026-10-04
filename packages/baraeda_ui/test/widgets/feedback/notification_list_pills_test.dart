// 알림 목록의 알약 구성(시안 `notifications*`) — 필터가 알약 둘 + 안 읽음 수가 되고, 빈 · 오류 · 불러오는 화면이
// 각자 모양을 갖는다. 기본(segmented)은 매니저 앱이 그대로 쓰므로 달라지지 않는다.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  NotificationListStyle style = NotificationListStyle.pills,
  List<int> items = const [],
  bool unreadOnly = false,
  int unreadCount = 3,
  bool isLoading = false,
  VoidCallback? onRetry,
  ValueChanged<bool>? onUnreadOnlyChanged,
}) => MaterialApp(
  theme: BaraedaTheme.light(),
  home: Scaffold(
    body: NotificationListView<int>(
      items: items,
      sentAtOf: (_) => DateTime(2026, 10, 3, 12),
      itemBuilder: (context, item) => Text('알림 $item'),
      now: DateTime(2026, 10, 3, 13),
      unreadOnly: unreadOnly,
      onUnreadOnlyChanged: onUnreadOnlyChanged ?? (_) {},
      onRefresh: () async {},
      onLoadMore: () {},
      style: style,
      unreadCount: unreadCount,
      isLoading: isLoading,
      onRetry: onRetry,
    ),
  ),
);

void main() {
  testWidgets('기본은 두 칸 전환이다 — 알약도 안 읽음 수도 없다', (tester) async {
    await tester.pumpWidget(_host(style: NotificationListStyle.segmented));

    expect(find.byType(BaraedaSegmentedControl), findsOneWidget);
    expect(find.byType(BaraedaFilterPill), findsNothing);
    expect(find.text('안 읽음'), findsOneWidget);
  });

  testWidgets('알약 구성은 [전체] · [안 읽음 N] 두 알약이고 누르면 걸러 보기가 바뀐다', (tester) async {
    bool? changed;
    await tester.pumpWidget(_host(onUnreadOnlyChanged: (v) => changed = v));

    expect(find.byType(BaraedaFilterPill), findsNWidgets(2));
    expect(find.byType(BaraedaSegmentedControl), findsNothing);
    expect(find.text('전체'), findsOneWidget);
    expect(find.text('안 읽음 3'), findsOneWidget);

    await tester.tap(find.text('안 읽음 3'));
    expect(changed, isTrue);
    await tester.tap(find.text('전체'));
    expect(changed, isFalse);
  });

  testWidgets('고른 알약이 표시된다 — 걸러 보기 상태가 알약에 나타난다', (tester) async {
    await tester.pumpWidget(_host(unreadOnly: true));

    final pills = tester.widgetList<BaraedaFilterPill>(
      find.byType(BaraedaFilterPill),
    );
    expect(pills.map((p) => p.selected), [false, true]);
  });

  testWidgets('비어 있으면 걸러 보기에 맞는 빈 화면 — 안 읽음에서는 전체 보기 단추가 있다', (tester) async {
    bool? changed;
    await tester.pumpWidget(
      _host(
        unreadOnly: true,
        unreadCount: 0,
        onUnreadOnlyChanged: (v) => changed = v,
      ),
    );

    expect(find.text('안 읽은 알림이 없어요'), findsOneWidget);
    expect(find.text('모두 확인했어요. 새 알림은 푸시로도 알려 드려요.'), findsOneWidget);
    await tester.tap(find.text('전체 알림 보기'));
    expect(changed, isFalse, reason: '전체 보기로 돌아간다');

    await tester.pumpWidget(_host(unreadCount: 0));
    expect(find.text('새 알림이 없어요'), findsOneWidget);
    expect(find.text('전체 알림 보기'), findsNothing);
  });

  testWidgets('오류 화면은 안내와 [다시 시도] 를 보여 주고 누르면 다시 받는다', (tester) async {
    var retried = 0;
    await tester.pumpWidget(_host(onRetry: () => retried++));

    expect(find.text('알림을 불러오지 못했어요'), findsOneWidget);
    expect(find.textContaining('새 알림은 푸시로는 계속 와요'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    expect(retried, 1);
  });

  testWidgets('불러오는 중에는 스피너 대신 목록 모양의 뼈대를 그린다', (tester) async {
    await tester.pumpWidget(_host(isLoading: true));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(BaraedaSkeletonRow), findsWidgets);
  });
}
