import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/ui/failure_message.dart';
import 'package:parent_app/features/notifications/presentation/notification_kind.dart';
import 'package:parent_app/features/notifications/presentation/notification_providers.dart';

/// P-09 · S-03 알림 탭 — §3.12 목록 · §3.13 읽음 처리 (UF-P-08).
///
/// 목록 그리기(걸러 보기 · 날짜 머리 · 다음 쪽 자동 받기 · 당겨서 새로고침)는
/// 공용 `NotificationListView` 가 맡는다. 이 화면은 받아 둔 목록·걸러 보기를 넣어 주고,
/// 행을 누르면 읽음 처리한 뒤 종류에 맞는 화면으로 보낸다.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(notificationFeedProvider);
    final filter = ref.watch(notificationFilterProvider);
    final notifier = ref.read(notificationFeedProvider.notifier);
    final feed = feedAsync.value;

    return Scaffold(
      appBar: const AppHeader(title: '알림'),
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
      title: _titleOf(item),
      body: item.body.isEmpty ? null : item.body,
      time: clockLabel(item.sentAt),
      timeSpoken: spokenClock(item.sentAt),
      unread: item.isUnread,
      important: kind.important,
      onTap: item.isUnread || kind.route != null
          ? () => _open(context, ref, item, kind.route)
          : null,
    );
  }
}

/// 자녀 이름(ATT-03)이 제목에도 본문에도 없으면 제목 뒤에 붙인다 — 자녀가 여럿일 때 누구 알림인지 알 수 있어야 한다.
String _titleOf(NotificationItem item) {
  final name = item.studentName;
  if (name == null || item.title.contains(name) || item.body.contains(name)) {
    return item.title;
  }
  return '${item.title} · $name';
}

/// 안 읽은 알림이면 읽음 처리하고, 종류에 맞는 화면이 있으면 그리로 간다(R32 P10).
Future<void> _open(
  BuildContext context,
  WidgetRef ref,
  NotificationItem item,
  String? route,
) async {
  if (route != null) unawaited(context.push<void>(route));
  if (!item.isUnread) return;
  try {
    await ref
        .read(notificationFeedProvider.notifier)
        .markRead(item.notificationId);
  } on Failure catch (failure) {
    // F05-13 — 읽음 처리가 실패해도 이동은 이미 끝났다. 알림은 안 읽음으로 남으니 알린다.
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failureMessage(failure, fallback: '읽음 처리하지 못했습니다'),
        ),
      ),
    );
  }
}
