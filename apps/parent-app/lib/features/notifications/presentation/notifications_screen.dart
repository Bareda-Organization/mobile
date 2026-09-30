import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/ui/failure_message.dart';
import 'package:parent_app/features/notifications/domain/notification_item.dart';
import 'package:parent_app/features/notifications/presentation/notification_kind.dart';
import 'package:parent_app/features/notifications/presentation/notification_providers.dart';
import 'package:parent_app/features/notifications/presentation/notification_time.dart';

/// 스크롤이 끝에서 이만큼(px) 안으로 들어오면 다음 쪽을 미리 받는다.
const double _loadMoreExtent = 300;

/// P-09 · S-03 알림 탭 — §3.12 목록 · §3.13 읽음 처리 (UF-P-08).
///
/// 날짜 머리 아래에 행이 쌓이고, 위에서 `[전체]` `[안 읽음]` 으로 거른다. 스크롤이 끝에 닿으면 다음 쪽을
/// 스스로 받고(§1.8 페이징), 당기면 새로고침한다. 행을 누르면 읽음 처리하고 종류에 맞는 화면으로 간다.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_loadMoreIfNearEnd);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_loadMoreIfNearEnd)
      ..dispose();
    super.dispose();
  }

  /// 끝이 가까우면 다음 쪽을 받는다. 화면이 짧아 스크롤 자체가 안 생겨도 그 자리에서 이어 받는다.
  void _loadMoreIfNearEnd() {
    if (!mounted || !_controller.hasClients) return;
    final feed = ref.read(notificationFeedProvider).value;
    if (feed == null ||
        !feed.hasNext ||
        feed.loadingMore ||
        feed.loadMoreFailed) {
      return;
    }
    if (_controller.position.extentAfter < _loadMoreExtent) {
      unawaited(ref.read(notificationFeedProvider.notifier).loadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(notificationFeedProvider);
    final filter = ref.watch(notificationFilterProvider);

    return Scaffold(
      appBar: const AppHeader(title: '알림'),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BaraedaSpacing.gutterMobile,
                BaraedaSpacing.space3,
                BaraedaSpacing.gutterMobile,
                BaraedaSpacing.space3,
              ),
              child: BaraedaSegmentedControl(
                block: true,
                options: const [
                  BaraedaSegmentedOption('all', label: '전체'),
                  BaraedaSegmentedOption('unread', label: '안 읽음'),
                ],
                value: filter.name,
                onChanged: (value) =>
                    ref.read(notificationFilterProvider.notifier).state =
                        NotificationFilter.values.byName(value),
              ),
            ),
            Expanded(
              child: feedAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Padding(
                  padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
                  child: AlertBanner(
                    tone: AlertTone.missed,
                    body: '알림을 불러오지 못했습니다',
                    action: BaraedaButton(
                      label: '다시 시도',
                      size: BaraedaButtonSize.sm,
                      variant: BaraedaButtonVariant.secondary,
                      onPressed: () => ref.invalidate(notificationFeedProvider),
                    ),
                  ),
                ),
                data: (feed) => _buildList(context, feed, filter),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    NotificationFeed feed,
    NotificationFilter filter,
  ) {
    // 다음 쪽 받기가 화면이 그려진 뒤에 일어나도록 — 빌드 중에 상태를 바꾸지 않는다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMoreIfNearEnd());

    final rows = _rowsOf(feed, ref.watch(clockProvider).now());
    return RefreshIndicator(
      onRefresh: () => ref.read(notificationFeedProvider.notifier).refresh(),
      child: rows.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                EmptyState(
                  icon: 'bell',
                  title: filter == NotificationFilter.unread
                      ? '안 읽은 알림이 없습니다'
                      : '새 알림이 없습니다',
                ),
              ],
            )
          : ListView.builder(
              controller: _controller,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: rows.length + (_hasFooter(feed) ? 1 : 0),
              itemBuilder: (context, index) => index == rows.length
                  ? _Footer(feed: feed)
                  : rows[index].build(context, ref),
            ),
    );
  }

  bool _hasFooter(NotificationFeed feed) =>
      feed.loadingMore || feed.loadMoreFailed;
}

/// 목록의 한 줄 — 날짜 머리 또는 알림 행.
sealed class _Row {
  Widget build(BuildContext context, WidgetRef ref);
}

class _HeaderRow implements _Row {
  const _HeaderRow(this.label);

  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          BaraedaSpacing.gutterMobile,
          BaraedaSpacing.space4,
          BaraedaSpacing.gutterMobile,
          BaraedaSpacing.space2,
        ),
        child: Text(
          label,
          style: BaraedaTypography.label.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}

class _ItemRow implements _Row {
  const _ItemRow(this.item);

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

/// 받은 알림을 날짜 머리로 묶은 줄 목록.
List<_Row> _rowsOf(NotificationFeed feed, DateTime now) {
  final rows = <_Row>[];
  String? lastHeader;
  for (final item in feed.items) {
    final header = dayHeader(item.sentAt, now);
    if (header != lastHeader) {
      rows.add(_HeaderRow(header));
      lastHeader = header;
    }
    rows.add(_ItemRow(item));
  }
  return rows;
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

/// 목록 맨 아래 — 다음 쪽을 받는 중이거나, 받기에 실패했을 때.
class _Footer extends ConsumerWidget {
  const _Footer({required this.feed});

  final NotificationFeed feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (feed.loadMoreFailed) {
      return Padding(
        padding: const EdgeInsets.all(BaraedaSpacing.space4),
        child: Column(
          children: [
            Text(
              '더 불러오지 못했습니다',
              style: BaraedaTypography.caption.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: BaraedaSpacing.space2),
            BaraedaButton(
              label: '다시 시도',
              size: BaraedaButtonSize.sm,
              variant: BaraedaButtonVariant.secondary,
              onPressed: () => unawaited(
                ref.read(notificationFeedProvider.notifier).loadMore(),
              ),
            ),
          ],
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(BaraedaSpacing.space4),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
