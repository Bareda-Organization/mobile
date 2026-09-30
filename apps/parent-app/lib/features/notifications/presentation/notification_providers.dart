import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';

/// 알림 목록 걸러 보기 — `[전체]` · `[안 읽음]`(`unread_only`).
enum NotificationFilter { all, unread }

final StateProvider<NotificationFilter> notificationFilterProvider =
    StateProvider<NotificationFilter>((ref) {
      ref.watch(currentUserRoleProvider); // 계정이 바뀌면 [전체] 로
      return NotificationFilter.all;
    });

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
      state = AsyncData(latest.withNextPage(next));
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
      state = AsyncData(
        latest == null
            ? NotificationFeed.first(head)
            : latest.withRefreshedHead(head),
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
    state = AsyncData(current.withRead(notificationId, readAt));
  }
}
