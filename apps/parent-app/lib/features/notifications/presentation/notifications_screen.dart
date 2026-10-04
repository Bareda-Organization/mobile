import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';
import 'package:parent_app/core/ui/failure_message.dart';
import 'package:parent_app/features/notifications/presentation/notification_kind.dart';
import 'package:parent_app/features/notifications/presentation/notification_providers.dart';

/// P-09 · S-03 알림 탭 — §3.12 목록 · §3.13 읽음 처리 (UF-P-08).
///
/// 목록 그리기(걸러 보기 · 날짜 머리 · 다음 쪽 자동 받기 · 당겨서 새로고침)는
/// 공용 `NotificationListView` 가 맡는다. 이 화면은 받아 둔 목록·걸러 보기를 넣어 주고,
/// 행을 누르면 읽음 처리한 뒤 종류에 맞는 화면으로 보낸다.
class NotificationsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(notificationFeedProvider);
    final filter = ref.watch(notificationFilterProvider);
    final notifier = ref.read(notificationFeedProvider.notifier);
    final feed = feedAsync.value;

    return Scaffold(
      appBar: AppHeader(title: '알림', subtitle: _subtitle(ref)),
      body: SafeArea(
        child: NotificationListView<NotificationItem>(
          style: NotificationListStyle.pills,
          unreadCount: feed?.unreadCount ?? 0,
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

/// 머리 아래 한 줄 — 서버가 보관하는 14일(§3.12)과, 학부모는 연결된 자녀 이름(알림이 누구 것인지 한눈에).
/// 학생은 본인뿐이라 이름을 덧붙이지 않는다. 자녀 목록은 못 받아도 이 줄에서 이름만 빠질 뿐이다.
String _subtitle(WidgetRef ref) {
  const base = '최근 14일';
  final isParent =
      ref.watch(roleCapabilitiesProvider)?.canToggleAttendance ?? false;
  if (!isParent) return base;
  final names = ref.watch(myStudentsProvider).value?.map((s) => s.name) ?? [];
  return [base, ...names].join(' · ');
}

class _ItemRow extends ConsumerWidget {
  const new({required this.item});

  final NotificationItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = kindOf(item.type);
    // 자녀 이름(ATT-03)은 제목이 아니라 종류 · 시각 줄 끝에 붙는다 — 학생은 본인뿐이라 붙이지 않는다.
    final isParent =
        ref.watch(roleCapabilitiesProvider)?.canToggleAttendance ?? false;
    return NotificationTile(
      style: NotificationTileStyle.card,
      icon: kind.icon,
      status: kind.status,
      kindLabel: kind.label,
      title: item.title,
      body: item.body.isEmpty ? null : item.body,
      time: clockLabel(item.sentAt),
      timeSpoken: spokenClock(item.sentAt),
      who: isParent ? item.studentName : null,
      unread: item.isUnread,
      important: kind.important,
      onTap: item.isUnread || kind.route != null
          ? () => _open(context, ref, item, kind.route)
          : null,
    );
  }
}

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
        content: WordWrapText(
          failureMessage(failure, fallback: '읽음 처리하지 못했습니다'),
        ),
      ),
    );
  }
}
