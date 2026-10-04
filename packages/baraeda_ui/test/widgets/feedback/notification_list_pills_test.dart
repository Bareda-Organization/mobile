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

Widget _cardHost({
  required List<DateTime> sentAt,
  bool read = false,
  VoidCallback? onTap,
  String? who = '이하준',
}) => MaterialApp(
  theme: BaraedaTheme.light(),
  home: Scaffold(
    body: NotificationListView<DateTime>(
      items: sentAt,
      sentAtOf: (t) => t,
      itemBuilder: (context, t) => NotificationTile(
        style: NotificationTileStyle.card,
        icon: 'clock',
        status: BaraedaStatus.moving,
        kindLabel: '지연',
        title: '버스가 10분 늦어요',
        body: '교통 체증으로 2호차가 10분 늦어요.',
        time: clockLabel(t),
        timeSpoken: spokenClock(t),
        unread: !read,
        who: who,
        onTap: onTap,
      ),
      now: DateTime.utc(2026, 10, 3, 4), // 10월 3일 13:00 KST (토)
      unreadOnly: false,
      onUnreadOnlyChanged: (_) {},
      onRefresh: () async {},
      onLoadMore: () {},
      style: NotificationListStyle.pills,
      unreadCount: 2,
    ),
  ),
);

void main() {
  group('카드형 행 · 날짜 머리 (시안 notifications)', () {
    final today = DateTime.utc(2026, 10, 3, 3, 12); // 12:12 KST
    final today2 = DateTime.utc(2026, 10, 3, 3, 10);
    final yesterday = DateTime.utc(2026, 10, 2, 7, 52);

    testWidgets('날짜 머리 오른쪽에 날짜가 붙는다 — 오늘은 요일까지, 어제는 날짜만', (tester) async {
      await tester.pumpWidget(_cardHost(sentAt: [today, today2, yesterday]));

      expect(find.text('오늘'), findsOneWidget);
      expect(find.text('10월 3일 (토)'), findsOneWidget);
      expect(find.text('어제'), findsOneWidget);
      expect(find.text('10월 2일'), findsOneWidget);
    });

    testWidgets('한 날의 행은 카드 하나로 묶인다 — 이틀이면 카드 둘', (tester) async {
      await tester.pumpWidget(_cardHost(sentAt: [today, today2, yesterday]));

      // 카드 안 행 수: 오늘 2 · 어제 1.
      expect(find.byType(NotificationTile), findsNWidgets(3));
      final dividers = find.byType(Divider);
      expect(dividers, findsNWidgets(1), reason: '오늘 카드의 두 행 사이 선 하나뿐');
    });

    testWidgets('행에 종류 알약 · 시각 · 자녀 이름이 한 줄로 있고 안 읽음 점이 있다', (tester) async {
      await tester.pumpWidget(_cardHost(sentAt: [today]));

      expect(find.text('버스가 10분 늦어요'), findsOneWidget);
      expect(find.text('지연'), findsOneWidget);
      expect(find.text('12:12'), findsOneWidget);
      expect(find.text('· 이하준'), findsOneWidget);
      expect(find.byKey(NotificationTile.unreadDotKey), findsOneWidget);
    });

    testWidgets('읽은 행은 점이 없고, 누를 수 있으면 쉐브론이 있다', (tester) async {
      await tester.pumpWidget(
        _cardHost(sentAt: [today], read: true, onTap: () {}),
      );

      expect(find.byKey(NotificationTile.unreadDotKey), findsNothing);
      expect(find.byType(BaraedaIcon), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (w) => w is BaraedaIcon && w.name == 'chevron-right',
        ),
        findsOneWidget,
      );
    });

    testWidgets('자녀 이름이 없으면 그 칸이 없다 — 학생 앱', (tester) async {
      await tester.pumpWidget(_cardHost(sentAt: [today], who: null));

      expect(find.textContaining('· '), findsNothing);
    });

    testWidgets('낭독은 안 읽음 · 종류 · 제목 · 본문 · 시각 · 자녀 이름을 한 번에 읽는다', (
      tester,
    ) async {
      await tester.pumpWidget(_cardHost(sentAt: [today]));

      expect(
        find.bySemanticsLabel(
          RegExp('안 읽음, 지연, 버스가 10분 늦어요, .*, 오후 12시 12분, 이하준'),
        ),
        findsOneWidget,
      );
    });
  });

  // Ruling 835 — 묶음은 알약 모양만의 것이 아니다. 기본(segmented · 매니저 앱)도 같은 규칙이다.
  Widget segmentedHost(List<DateTime> sentAt) => MaterialApp(
    theme: BaraedaTheme.light(),
    home: Scaffold(
      body: NotificationListView<DateTime>(
        items: sentAt,
        sentAtOf: (t) => t,
        itemBuilder: (context, t) => Text('알림 ${t.toIso8601String()}'),
        now: DateTime.utc(2026, 10, 3, 4),
        unreadOnly: false,
        onUnreadOnlyChanged: (_) {},
        onRefresh: () async {},
        onLoadMore: () {},
      ),
    ),
  );

  testWidgets('기본 모양(row)도 한 날의 행을 카드 하나로 묶고 날짜 머리에 날짜는 없다', (tester) async {
    final today = DateTime.utc(2026, 10, 3, 3, 12);
    final today2 = DateTime.utc(2026, 10, 3, 3, 10);
    final yesterday = DateTime.utc(2026, 10, 2, 7, 52);
    await tester.pumpWidget(segmentedHost([today, today2, yesterday]));

    expect(find.text('오늘'), findsOneWidget);
    expect(find.text('어제'), findsOneWidget);
    expect(find.text('10월 3일 (토)'), findsNothing);
    expect(find.text('10월 2일'), findsNothing);
    // 카드 안 행 수: 오늘 2 · 어제 1 → 카드 둘, 사이 선은 오늘 카드의 한 줄뿐.
    expect(find.byType(Divider), findsNWidgets(1));
  });

  testWidgets('기본 모양에서 서울 자정~오전 9시 알림도 서울 날짜로 묶인다', (tester) async {
    // 지금 10-04 08:30 KST. 10-03 23:50 KST(= 14:50 UTC)는 어제,
    // 10-04 07:00 KST(= 10-03 22:00 UTC)는 오늘.
    await tester.pumpWidget(
      MaterialApp(
        theme: BaraedaTheme.light(),
        home: Scaffold(
          body: NotificationListView<DateTime>(
            items: [
              DateTime.utc(2026, 10, 3, 22),
              DateTime.utc(2026, 10, 3, 14, 50),
            ],
            sentAtOf: (t) => t,
            itemBuilder: (context, t) => Text('알림 ${t.hour}'),
            now: DateTime.utc(2026, 10, 3, 23, 30),
            unreadOnly: false,
            onUnreadOnlyChanged: (_) {},
            onRefresh: () async {},
            onLoadMore: () {},
          ),
        ),
      ),
    );

    expect(find.text('오늘'), findsOneWidget);
    expect(find.text('어제'), findsOneWidget);
    expect(find.byType(Divider), findsNothing, reason: '각 카드에 행이 하나씩');
  });

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

  // Ruling 835 정정 — 행 시각의 날짜는 날짜 머리에 날짜가 없을 때만 붙는다(날짜를 두 번 쓰지 않는다).
  group('행 시각의 날짜는 머리에 날짜가 없을 때만 붙는다', () {
    final now = DateTime.utc(2026, 10, 3, 3, 14); // 10-03 12:14 KST
    final today = DateTime.utc(2026, 10, 3, 3, 12);
    final yesterday = DateTime.utc(2026, 10, 2, 7, 52); // 10-02 16:52 KST

    test('알약 모양은 머리 오른쪽에 날짜가 있어 지난 날짜 행도 시각만이다', () {
      expect(NotificationListStyle.pills.rowTime(yesterday, now), '16:52');
    });

    test('두 칸 전환 모양은 머리에 날짜가 없어 지난 날짜 행에 날짜가 붙는다', () {
      expect(
        NotificationListStyle.segmented.rowTime(yesterday, now),
        '10월 2일 16:52',
      );
    });

    // 머리 글자 자체가 날짜(`9월 28일(월)`)인 날은 어느 모양이든 머리가 이미 날짜를
    // 말한다 — 날짜 없는 머리는 `어제` 뿐이다.
    test('두 칸 전환 모양도 머리 글자가 날짜인 날의 행은 시각만이다', () {
      final older = DateTime.utc(2026, 9, 28, 5, 5); // 9-28 14:05 KST

      expect(dayHeader(older, now), '9월 28일(월)');
      expect(NotificationListStyle.segmented.rowTime(older, now), '14:05');
    });

    test('오늘 행은 어느 모양이든 시각만이다', () {
      for (final style in NotificationListStyle.values) {
        expect(style.rowTime(today, now), '12:12', reason: '$style');
      }
    });

    // 행 시각의 형식은 `headerShowsDate` 로 고르니, 이 값이 실제로 머리가 그리는 것과 같아야 둘이 어긋나지 않는다.
    testWidgets('headerShowsDate 는 날짜 머리가 실제로 오른쪽 날짜를 그리는지와 같다', (
      tester,
    ) async {
      for (final style in NotificationListStyle.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: BaraedaTheme.light(),
            home: Scaffold(
              body: NotificationListView<DateTime>(
                items: [today, yesterday],
                sentAtOf: (t) => t,
                itemBuilder: (context, t) => const SizedBox(height: 20),
                now: now,
                unreadOnly: false,
                onUnreadOnlyChanged: (_) {},
                onRefresh: () async {},
                onLoadMore: () {},
                style: style,
              ),
            ),
          ),
        );

        // 어제 머리의 오른쪽 날짜 — 그리면 `10월 2일` 글자가 하나 보인다.
        expect(
          find.text('10월 2일').evaluate().length == 1,
          style.headerShowsDate,
          reason: '$style',
        );
      }
    });
  });
}
