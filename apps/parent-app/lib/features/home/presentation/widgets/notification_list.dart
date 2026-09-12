import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/features/home/domain/notification_item.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';

/// §3.12 알림 1페이지를 홈 화면에 압축해 보여준다(§1.8 — 무한 스크롤이
/// 아니라 1페이지). 항목을 누르면 §3.13 로 읽음 처리한다.
class NotificationList extends ConsumerWidget {
  const NotificationList({required this.page, required this.now, super.key});

  final NotificationPage page;

  /// 상대 시각(`n분 전`) 계산 기준 시각 — 위젯 안에서 `DateTime.now()` 를
  /// 직접 부르지 않는다(CONVENTIONS_FLUTTER.md §6). 호출부(`home_screen.dart`)
  /// 가 한 곳에서만 실 시각을 주입해, 이 위젯은 시험에서 고정 시각으로
  /// 검증할 수 있다.
  final DateTime now;

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
      time: _relativeTime(item.sentAt, now),
      unread: item.isUnread,
      onTap: item.isUnread ? () => _markRead(ref, item.notificationId) : null,
    );
  }

  Future<void> _markRead(WidgetRef ref, String notificationId) async {
    await ref.read(notificationRepositoryProvider).markRead(notificationId);
    ref.invalidate(notificationsProvider);
  }
}

String _relativeTime(DateTime sentAt, DateTime now) {
  final diff = now.difference(sentAt);
  if (diff.inMinutes < 1) return '방금 전';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  return '${diff.inDays}일 전';
}
