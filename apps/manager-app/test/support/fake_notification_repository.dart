import 'package:baraeda_core/baraeda_core.dart';

/// 서버처럼 걸러 보기·쪽 나누기·읽음 처리를 흉내 내고, 받은 요청을 기록하는 가짜.
///
/// `unread_count` 는 서버처럼 걸러 보기와 무관하게 **전체** 안 읽은 수다(§3.12).
class FakeNotificationRepository implements NotificationRepository {
  new(List<NotificationItem> items)
    : _items = [...items];

  List<NotificationItem> _items;

  final requests = <({int page, int size, bool unreadOnly})>[];
  final marked = <String>[];

  /// 채워 두면 [getNotifications] 가 던진다. 특정 쪽에서만 던지려면 [failOnPage].
  Failure? getFailure;
  int? failOnPage;

  /// 채워 두면 [markRead] 가 던진다.
  Failure? markFailure;

  int get unreadCount => _items.where((item) => item.isUnread).length;

  @override
  Future<NotificationPage> getNotifications({
    int page = 0,
    int size = 20,
    bool unreadOnly = false,
  }) async {
    requests.add((page: page, size: size, unreadOnly: unreadOnly));
    if (getFailure != null && (failOnPage == null || failOnPage == page)) {
      // Failure 는 Exception/Error 를 상속하지 않는다 — 리포지토리가 던지는 형태 그대로.
      // ignore: only_throw_errors
      throw getFailure!;
    }
    final matched = unreadOnly
        ? _items.where((item) => item.isUnread).toList()
        : _items;
    final from = page * size;
    final slice = matched.skip(from).take(size).toList();
    return NotificationPage(
      items: slice,
      page: page,
      size: size,
      totalCount: matched.length,
      hasNext: from + slice.length < matched.length,
      unreadCount: unreadCount,
    );
  }

  @override
  Future<void> markRead(String notificationId) async {
    // 위와 같은 이유.
    // ignore: only_throw_errors
    if (markFailure != null) throw markFailure!;
    marked.add(notificationId);
    _items = [
      for (final item in _items)
        if (item.notificationId == notificationId && item.isUnread)
          item.markedRead(DateTime.utc(2026, 9, 30, 1))
        else
          item,
    ];
  }
}
