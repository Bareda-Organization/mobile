import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/features/notifications/presentation/notification_kind.dart';
import 'package:manager_app/features/notifications/presentation/notification_providers.dart';

/// 알림 목록(NTF-08 · §3.12) — 홈 머리말 [알림] 에서 들어온다. 운행 중 화면(운전 화면·명단)에는 진입점이 없다.
///
/// 목록 그리기(걸러 보기 · 날짜 머리 · 다음 쪽 자동 받기 · 당겨서 새로고침)는
/// 학부모·학생 앱과 같은 공용 `NotificationListView` 가 맡는다.
/// 행을 누르면 읽음 처리(§3.13)한다 — 갈 화면은 없다(`notification_kind.dart`).
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(notificationFeedProvider);
    final filter = ref.watch(notificationFilterProvider);
    final notifier = ref.read(notificationFeedProvider.notifier);
    final feed = feedAsync.value;

    return Scaffold(
      appBar: AppBar(title: const Text('알림')),
      body: SafeArea(
        child: NotificationListView<NotificationItem>(
          items: feed?.items ?? const [],
          sentAtOf: (item) => item.sentAt,
          now: ref.watch(clockProvider).now(),
          unreadOnly: filter == NotificationFilter.unread,
          onUnreadOnlyChanged: (unreadOnly) =>
              ref.read(notificationFilterProvider.notifier).state = unreadOnly
              ? NotificationFilter.unread
              : NotificationFilter.all,
          isLoading: feedAsync.isLoading && feed == null,
          onRetry: feedAsync.hasError && feed == null
              ? () => ref.invalidate(notificationFeedProvider)
              : null,
          hasNext: feed?.hasNext ?? false,
          loadingMore: feed?.loadingMore ?? false,
          loadMoreFailed: feed?.loadMoreFailed ?? false,
          onRefresh: notifier.refresh,
          onLoadMore: () => unawaited(notifier.loadMore()),
          itemBuilder: (context, item) => _ItemRow(item: item),
        ),
      ),
    );
  }
}

class _ItemRow extends ConsumerWidget {
  const _ItemRow({required this.item});

  final NotificationItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = kindOf(item.type);
    return NotificationTile(
      icon: kind.icon,
      status: kind.status,
      kindLabel: kind.label,
      title: item.title,
      body: item.body.isEmpty ? null : item.body,
      time: clockLabel(item.sentAt),
      timeSpoken: spokenClock(item.sentAt),
      unread: item.isUnread,
      important: kind.important,
      onTap: item.isUnread ? () => _markRead(context, ref) : null,
    );
  }

  /// 읽음 처리. 실패하면 안 읽음으로 남으니 알린다.
  Future<void> _markRead(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(notificationFeedProvider.notifier)
          .markRead(item.notificationId);
    } on Failure catch (failure) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeFailure(failure))),
      );
    }
  }
}
