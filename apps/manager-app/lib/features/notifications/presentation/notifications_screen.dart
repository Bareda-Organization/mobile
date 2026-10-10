import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/features/notifications/presentation/notification_kind.dart';
import 'package:manager_app/features/notifications/presentation/notification_providers.dart';
import 'package:manager_app/features/notifications/presentation/widgets/manager_notification_row.dart';

/// 목록 모양 — 행 시각의 형식도 이 모양으로 정해진다(머리에 날짜가 없어 지난 날짜 행에 날짜가 붙는다, Ruling 835).
const NotificationListStyle _listStyle = NotificationListStyle.segmented;

/// 알림 목록(NTF-08 · §3.12) — 아래 탭의 [알림] 에서 들어온다(`Ruling 857`).
/// 기사가 운전하는 화면에는 진입점·배지가 없다. 동승자 명단은 탭 안의 화면이라
/// 알림 배지가 보여도 된다(동승자는 운전하지 않는다).
///
/// 목록 그리기(걸러 보기 · 날짜 머리 · 다음 쪽 자동 받기 · 당겨서 새로고침)는
/// 학부모·학생 앱과 같은 공용 `NotificationListView` 가 맡는다.
/// 행을 누르면 읽음 처리(§3.13)하고, 회차를 가리키는 알림(노선·배치 변경)은 그 회차의 화면으로 간다
/// (`notification_kind.dart` 의 `destinationOf`).
class NotificationsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(notificationFeedProvider);
    final filter = ref.watch(notificationFilterProvider);
    final notifier = ref.read(notificationFeedProvider.notifier);
    final feed = feedAsync.value;

    return Scaffold(
      appBar: const ManagerHeader(title: '알림'),
      body: SafeArea(
        child: NotificationListView<NotificationItem>(
          // 기본값과 같아도 명시한다 — 목록 모양과 행 시각 형식이 같은 상수로 함께 움직이게.
          // ignore: avoid_redundant_argument_values
          style: _listStyle,
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
  const new({required this.item});

  final NotificationItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = kindOf(item.type);
    final now = ref.watch(clockProvider).now();
    return ManagerNotificationRow(
      icon: kind.icon,
      kindLabel: kind.label,
      title: item.title,
      body: item.body.isEmpty ? null : item.body,
      time: _listStyle.rowTime(item.sentAt, now),
      timeSpoken: spokenTime(item.sentAt, now),
      unread: item.isUnread,
      important: kind.important,
      onTap: _tapHandler(context, ref),
    );
  }

  /// 안 읽은 알림은 읽음 처리하고, 가리키는 회차가 있으면 그 화면으로 간다(Ruling 542). 둘 다 해당 없으면 `null`.
  VoidCallback? _tapHandler(BuildContext context, WidgetRef ref) {
    final destination = item.runId == null
        ? null
        : destinationOf(
            item.type,
            canOperateRun:
                ref.read(roleCapabilitiesProvider)?.canOperateRun ?? false,
          );
    if (!item.isUnread && destination == null) return null;
    return () {
      if (item.isUnread) unawaited(_markRead(context, ref));
      if (destination != null) {
        ref.read(selectedRunIdProvider.notifier).state = item.runId;
        // 명단은 동승자의 탭이라 탭을 바꿔 가고, 운행 준비는 위에 덮어 연다.
        if (destination == AppRoutes.roster) {
          context.go(destination);
        } else {
          unawaited(context.push(destination));
        }
      }
    };
  }

  /// 읽음 처리. 실패하면 안 읽음으로 남으니 알린다.
  Future<void> _markRead(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(notificationFeedProvider.notifier)
          .markRead(item.notificationId);
    } on Failure catch (failure) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: WordWrapText(describeFailure(failure))));
    }
  }
}
