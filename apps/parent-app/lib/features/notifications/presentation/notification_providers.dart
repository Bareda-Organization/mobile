import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/features/notifications/domain/notification_item.dart';
import 'package:parent_app/features/notifications/domain/notification_repository.dart';

/// 알림 목록 걸러 보기 — `[전체]` · `[안 읽음]`(`unread_only`).
enum NotificationFilter { all, unread }

final StateProvider<NotificationFilter> notificationFilterProvider =
    StateProvider<NotificationFilter>((ref) {
      ref.watch(currentUserRoleProvider); // 계정이 바뀌면 [전체] 로
      return NotificationFilter.all;
    });

/// 지금까지 받은 알림 쪽들을 이어 붙인 목록 — 알림 화면과 탭 배지가 함께 본다.
@immutable
class NotificationFeed {
  const NotificationFeed({
    required this.items,
    required this.page,
    required this.hasNext,
    required this.unreadCount,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  factory NotificationFeed.first(NotificationPage page) => NotificationFeed(
    items: page.items,
    page: page.page,
    hasNext: page.hasNext,
    unreadCount: page.unreadCount,
  );

  final List<NotificationItem> items;

  /// 마지막으로 받은 쪽 번호(0부터).
  final int page;
  final bool hasNext;

  /// 탭 배지 — 걸러 보기와 무관하게 서버가 세는 전체 안 읽은 수(§3.12).
  final int unreadCount;
  final bool loadingMore;

  /// 다음 쪽 받기가 실패했다 — 사용자가 [다시 시도] 를 누를 때까지 자동으로 다시 받지 않는다.
  final bool loadMoreFailed;

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
}

/// §3.12 — 알림 목록. 첫 쪽을 받고, `loadMore` 가 다음 쪽을 이어 붙인다.
///
/// 걸러 보기가 바뀌거나 계정이 바뀌면(로그아웃 = 역할 null · F05-01) 처음부터 다시 받는다.
final notificationFeedProvider =
    AsyncNotifierProvider<NotificationFeedNotifier, NotificationFeed>(
      NotificationFeedNotifier.new,
    );

class NotificationFeedNotifier extends AsyncNotifier<NotificationFeed> {
  @override
  Future<NotificationFeed> build() async {
    ref.watch(currentUserRoleProvider);
    final filter = ref.watch(notificationFilterProvider);
    final page = await _repository.getNotifications(
      unreadOnly: filter == NotificationFilter.unread,
    );
    return NotificationFeed.first(page);
  }

  bool get _unreadOnly =>
      ref.read(notificationFilterProvider) == NotificationFilter.unread;

  NotificationRepository get _repository =>
      ref.read(notificationRepositoryProvider);

  /// 다음 쪽을 받아 이어 붙인다. 실패하면 목록은 그대로 두고 [NotificationFeed.loadMoreFailed] 를 켠다.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasNext || current.loadingMore) return;
    state = AsyncData(
      current.copyWith(loadingMore: true, loadMoreFailed: false),
    );
    final unreadOnly = _unreadOnly;
    try {
      final next = await _repository.getNotifications(
        page: current.page + 1,
        unreadOnly: unreadOnly,
      );
      final latest = state.value;
      // 기다리는 사이 걸러 보기가 바뀌었거나 새로고침이 목록을 갈아 끼웠으면 이 결과는 버린다.
      if (latest == null ||
          _unreadOnly != unreadOnly ||
          latest.page != current.page) {
        return;
      }
      state = AsyncData(
        latest.copyWith(
          items: _appendNew(latest.items, next.items),
          page: next.page,
          hasNext: next.hasNext,
          unreadCount: next.unreadCount,
          loadingMore: false,
        ),
      );
    } on Failure {
      final latest = state.value;
      if (latest == null) return;
      state = AsyncData(
        latest.copyWith(loadingMore: false, loadMoreFailed: true),
      );
    }
  }

  /// 첫 쪽을 다시 받아 맨 앞에 합친다 — 이미 받아 둔 뒤쪽 알림은 그대로 두어 읽던 자리가 튀지 않는다.
  /// 실패하면 보이던 목록을 지우지 않는다(목록이 아직 없을 때만 오류로 둔다).
  Future<void> refresh() async {
    final current = state.value;
    try {
      final head = await _repository.getNotifications(unreadOnly: _unreadOnly);
      final latest = state.value ?? current;
      if (latest == null || latest.page == 0) {
        state = AsyncData(NotificationFeed.first(head));
        return;
      }
      final headIds = {for (final item in head.items) item.notificationId};
      state = AsyncData(
        latest.copyWith(
          items: [
            ...head.items,
            ...latest.items.where((i) => !headIds.contains(i.notificationId)),
          ],
          unreadCount: head.unreadCount,
        ),
      );
    } on Failure catch (failure, stack) {
      if (current == null) state = AsyncError(failure, stack);
    }
  }

  /// §3.13 읽음 처리 — 성공하면 그 행만 읽음으로 바꾸고 안 읽은 수를 하나 줄인다(배지가 바로 준다).
  /// 실패는 호출한 화면이 안내하도록 그대로 던진다(F05-13).
  Future<void> markRead(String notificationId) async {
    await _repository.markRead(notificationId);
    final current = state.value;
    if (current == null) return;
    final readAt = ref.read(clockProvider).now();
    var changed = false;
    final items = [
      for (final item in current.items)
        if (item.notificationId == notificationId && item.isUnread)
          () {
            changed = true;
            return item.markedRead(readAt);
          }()
        else
          item,
    ];
    if (!changed) return;
    state = AsyncData(
      current.copyWith(
        items: items,
        unreadCount: current.unreadCount > 0 ? current.unreadCount - 1 : 0,
      ),
    );
  }
}

List<NotificationItem> _appendNew(
  List<NotificationItem> existing,
  List<NotificationItem> more,
) {
  final ids = {for (final item in existing) item.notificationId};
  return [...existing, ...more.where((i) => !ids.contains(i.notificationId))];
}
