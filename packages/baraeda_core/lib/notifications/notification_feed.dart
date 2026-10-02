import 'package:baraeda_core/notifications/notification_item.dart';
import 'package:flutter/foundation.dart';

/// 지금까지 받은 알림 쪽들을 이어 붙인 목록 — 알림 화면과 탭 배지·홈 배지가 함께 본다.
///
/// 불변 값이고, 쪽 이어 붙이기·새로고침 합치기·읽음 표시는 새 값을 돌려주는 순수 함수다.
/// 상태 보관(Riverpod)은 각 앱이 맡는다 — 두 앱이 같은 규칙을 쓰도록 계산만 여기에 둔다.
@immutable
class NotificationFeed {
  /// 받아 둔 알림·쪽 상태를 그대로 담는다.
  const new({
    required this.items,
    required this.page,
    required this.hasNext,
    required this.unreadCount,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  /// 첫 쪽만 받은 상태.
  factory first(NotificationPage page) => NotificationFeed(
    items: page.items,
    page: page.page,
    hasNext: page.hasNext,
    unreadCount: page.unreadCount,
  );

  /// 지금까지 받은 알림(최신이 앞).
  final List<NotificationItem> items;

  /// 마지막으로 받은 쪽 번호(0부터).
  final int page;

  /// 서버에 다음 쪽이 더 있는가.
  final bool hasNext;

  /// 배지 — 걸러 보기와 무관하게 서버가 세는 전체 안 읽은 수(§3.12).
  final int unreadCount;

  /// 다음 쪽을 받는 중인가.
  final bool loadingMore;

  /// 다음 쪽 받기가 실패했다 — 사용자가 [다시 시도] 를 누를 때까지 자동으로 다시 받지 않는다.
  final bool loadMoreFailed;

  /// 바꿀 값만 지정한 사본.
  NotificationFeed copyWith({
    List<NotificationItem>? items,
    int? page,
    bool? hasNext,
    int? unreadCount,
    bool? loadingMore,
    bool? loadMoreFailed,
  }) => NotificationFeed(
    items: items ?? this.items,
    page: page ?? this.page,
    hasNext: hasNext ?? this.hasNext,
    unreadCount: unreadCount ?? this.unreadCount,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
  );

  /// 다음 쪽 [next] 를 뒤에 이어 붙인다 — 이미 있는 알림은 건너뛴다.
  NotificationFeed withNextPage(NotificationPage next) {
    final ids = {for (final item in items) item.notificationId};
    return copyWith(
      items: [
        ...items,
        ...next.items.where((i) => !ids.contains(i.notificationId)),
      ],
      page: next.page,
      hasNext: next.hasNext,
      unreadCount: next.unreadCount,
      loadingMore: false,
    );
  }

  /// 새로 받은 첫 쪽 [head] 를 맨 앞에 합친다 — 이미 받아 둔 뒤쪽 알림은 그대로 두어 읽던 자리가 튀지 않는다.
  /// 아직 첫 쪽만 받은 상태면 목록을 통째로 갈아 끼운다.
  NotificationFeed withRefreshedHead(NotificationPage head) {
    if (page == 0) return NotificationFeed.first(head);
    final headIds = {for (final item in head.items) item.notificationId};
    return copyWith(
      items: [
        ...head.items,
        ...items.where((i) => !headIds.contains(i.notificationId)),
      ],
      unreadCount: head.unreadCount,
    );
  }

  /// [notificationId] 를 읽음으로 바꾸고 안 읽은 수를 하나 줄인다. 이미 읽었거나 목록에 없으면 그대로다.
  NotificationFeed withRead(String notificationId, DateTime readAt) {
    var changed = false;
    final next = [
      for (final item in items)
        if (item.notificationId == notificationId && item.isUnread)
          () {
            changed = true;
            return item.markedRead(readAt);
          }()
        else
          item,
    ];
    if (!changed) return this;
    return copyWith(
      items: next,
      unreadCount: unreadCount > 0 ? unreadCount - 1 : 0,
    );
  }
}
