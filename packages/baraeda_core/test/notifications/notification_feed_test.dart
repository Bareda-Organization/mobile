import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationItem _item(String id, {DateTime? readAt}) => NotificationItem(
  notificationId: id,
  type: 'route_changed',
  title: '노선 변경',
  body: '본문',
  sentAt: DateTime.utc(2026, 10),
  popup: false,
  readAt: readAt,
);

NotificationPage _page(
  List<NotificationItem> items, {
  int page = 0,
  bool hasNext = false,
  int unread = 0,
}) => NotificationPage(
  items: items,
  page: page,
  size: 20,
  totalCount: items.length,
  hasNext: hasNext,
  unreadCount: unread,
);

/// 두 앱이 같은 규칙으로 목록을 잇고 읽음 표시를 하도록 계산만 모아 둔 값 객체의 시험.
void main() {
  test('다음 쪽을 이어 붙일 때 이미 있는 알림은 건너뛴다', () {
    final feed = NotificationFeed.first(
      _page([_item('1'), _item('2')], hasNext: true, unread: 2),
    );

    final next = feed.withNextPage(
      _page([_item('2'), _item('3')], page: 1, unread: 1),
    );

    expect(next.items.map((i) => i.notificationId), ['1', '2', '3']);
    expect(next.page, 1);
    expect(next.hasNext, isFalse);
    expect(next.unreadCount, 1);
  });

  test('읽음 표시는 그 행만 바꾸고 안 읽은 수를 하나 줄이며, 이미 읽은 행에는 다시 줄이지 않는다', () {
    final feed = NotificationFeed.first(_page([_item('1')], unread: 1));
    final at = DateTime.utc(2026, 10, 1, 1);

    final read = feed.withRead('1', at);

    expect(read.items.single.isUnread, isFalse);
    expect(read.unreadCount, 0);
    expect(read.withRead('1', at).unreadCount, 0);
    expect(read.withRead('없는 알림', at), same(read));
  });

  test('새로고침은 첫 쪽을 앞에 합치고 뒤쪽에 받아 둔 알림은 남긴다', () {
    final feed = NotificationFeed.first(
      _page([_item('2')], hasNext: true, unread: 1),
    ).withNextPage(_page([_item('1')], page: 1, unread: 1));

    final refreshed = feed.withRefreshedHead(
      _page([_item('3'), _item('2')], hasNext: true, unread: 2),
    );

    expect(refreshed.items.map((i) => i.notificationId), ['3', '2', '1']);
    expect(refreshed.unreadCount, 2);
    expect(refreshed.page, 1);
  });
}
