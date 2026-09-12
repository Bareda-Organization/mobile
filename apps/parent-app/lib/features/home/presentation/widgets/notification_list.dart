import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/features/home/domain/notification_item.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';

/// §3.12 알림 1페이지를 홈 화면에 압축해 보여준다(§1.8 — 무한 스크롤이
/// 아니라 1페이지). 항목을 누르면 §3.13 로 읽음 처리한다.
class NotificationList extends ConsumerWidget {
  const NotificationList({required this.page, super.key});

  final NotificationPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (page.items.isEmpty) {
      return const EmptyState(icon: 'bell', title: '새 알림이 없습니다');
    }

    return Column(
      children: page.items
          .map((item) => _buildTile(context, ref, item))
          .toList(),
    );
  }

  Widget _buildTile(
    BuildContext context,
    WidgetRef ref,
    NotificationItem item,
  ) {
    return NotificationCard(
      title: item.title,
      sub: item.body,
      meta: item.studentName,
      time: _relativeTime(item.sentAt),
      unread: item.isUnread,
      onTap: item.isUnread ? () => _markRead(ref, item.notificationId) : null,
    );
  }

  Future<void> _markRead(WidgetRef ref, String notificationId) async {
    await ref.read(notificationRepositoryProvider).markRead(notificationId);
    ref.invalidate(notificationsProvider);
  }
}

String _relativeTime(DateTime sentAt) {
  final diff = DateTime.now().difference(sentAt);
  if (diff.inMinutes < 1) return '방금 전';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  return '${diff.inDays}일 전';
}
