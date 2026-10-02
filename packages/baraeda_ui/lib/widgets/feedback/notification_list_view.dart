import 'dart:async';

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/button.dart';
import 'package:baraeda_ui/widgets/feedback/alert_banner.dart';
import 'package:baraeda_ui/widgets/feedback/empty_state.dart';
import 'package:baraeda_ui/widgets/feedback/notification_time.dart';
import 'package:baraeda_ui/widgets/forms/segmented_control.dart';
import 'package:flutter/material.dart';

/// 스크롤이 끝에서 이만큼(px) 안으로 들어오면 다음 쪽을 미리 받는다.
const double _loadMoreExtent = 300;

/// 알림 목록 화면의 본문 — `[전체]` `[안 읽음]` 걸러 보기 · 날짜 머리 · 스크롤 끝에서 다음 쪽 자동 받기 ·
/// 당겨서 새로고침 · 빈/오류 화면. 학부모·학생 앱과 매니저 앱이 함께 쓴다(R44 · R46).
///
/// 이 위젯은 **그리기만** 한다. 알림 목록과 쪽 상태는 앱이 들고
/// ([items] · [hasNext] · [loadingMore] …) 이 위젯이 부르는 콜백으로만 바꾼다.
/// 한 줄 그리기는 [itemBuilder] 가 맡아 앱마다 종류 표·이동 경로가 다를 수 있다.
class NotificationListView<T> extends StatefulWidget {
  /// 목록 상태와 콜백을 받아 그린다.
  const new({
    required this.items,
    required this.sentAtOf,
    required this.itemBuilder,
    required this.now,
    required this.unreadOnly,
    required this.onUnreadOnlyChanged,
    required this.onRefresh,
    required this.onLoadMore,
    super.key,
    this.isLoading = false,
    this.onRetry,
    this.hasNext = false,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  /// 받아 둔 알림(최신이 앞).
  final List<T> items;

  /// 날짜 머리를 묶는 기준 — 항목의 발송 시각.
  final DateTime Function(T item) sentAtOf;

  /// 알림 한 건을 그리는 행.
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// 날짜 머리의 `오늘` · `어제` 를 정하는 지금 시각.
  final DateTime now;

  /// `[안 읽음]` 이 선택돼 있는가.
  final bool unreadOnly;

  /// `[전체]` · `[안 읽음]` 을 눌렀다.
  final ValueChanged<bool> onUnreadOnlyChanged;

  /// 당겨서 새로고침.
  final Future<void> Function() onRefresh;

  /// 끝에 가까워졌다 — 다음 쪽을 받는다.
  final VoidCallback onLoadMore;

  /// 첫 쪽을 받는 중 — 스피너.
  final bool isLoading;

  /// `null` 이 아니면 첫 쪽 받기가 실패한 것이다 — 오류 띠와 이 콜백을 부르는 `다시 시도`.
  final VoidCallback? onRetry;

  /// 서버에 다음 쪽이 더 있는가.
  final bool hasNext;

  /// 다음 쪽을 받는 중인가.
  final bool loadingMore;

  /// 다음 쪽 받기가 실패했다 — 사용자가 `다시 시도` 를 누를 때까지 자동으로 다시 받지 않는다.
  final bool loadMoreFailed;

  @override
  State<NotificationListView<T>> createState() =>
      _NotificationListViewState<T>();
}

class _NotificationListViewState<T> extends State<NotificationListView<T>> {
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
    final w = widget;
    if (!w.hasNext || w.loadingMore || w.loadMoreFailed) return;
    if (_controller.position.extentAfter < _loadMoreExtent) w.onLoadMore();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return Column(
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
            value: w.unreadOnly ? 'unread' : 'all',
            onChanged: (value) => w.onUnreadOnlyChanged(value == 'unread'),
          ),
        ),
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final w = widget;
    if (w.isLoading) return const Center(child: CircularProgressIndicator());
    final onRetry = w.onRetry;
    if (onRetry != null) {
      return Padding(
        padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
        child: AlertBanner(
          tone: AlertTone.missed,
          body: '알림을 불러오지 못했습니다',
          action: BaraedaButton(
            label: '다시 시도',
            size: BaraedaButtonSize.sm,
            variant: BaraedaButtonVariant.secondary,
            onPressed: onRetry,
          ),
        ),
      );
    }

    // 다음 쪽 받기가 화면이 그려진 뒤에 일어나도록 — 빌드 중에 상태를 바꾸지 않는다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMoreIfNearEnd());

    final rows = _rows();
    return RefreshIndicator(
      onRefresh: w.onRefresh,
      child: rows.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                EmptyState(
                  icon: 'bell',
                  title: w.unreadOnly ? '안 읽은 알림이 없습니다' : '새 알림이 없습니다',
                ),
              ],
            )
          : ListView.builder(
              controller: _controller,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: rows.length + (_hasFooter ? 1 : 0),
              itemBuilder: (context, index) =>
                  index == rows.length ? _footer(context) : rows[index](),
            ),
    );
  }

  bool get _hasFooter => widget.loadingMore || widget.loadMoreFailed;

  /// 날짜 머리와 알림 행을 한 줄씩 만드는 빌더 목록.
  List<Widget Function()> _rows() {
    final w = widget;
    final rows = <Widget Function()>[];
    String? lastHeader;
    for (final item in w.items) {
      final header = dayHeader(w.sentAtOf(item), w.now);
      if (header != lastHeader) {
        rows.add(() => _DayHeader(label: header));
        lastHeader = header;
      }
      rows.add(() => w.itemBuilder(context, item));
    }
    return rows;
  }

  /// 목록 맨 아래 — 다음 쪽을 받는 중이거나, 받기에 실패했을 때.
  Widget _footer(BuildContext context) {
    if (widget.loadMoreFailed) {
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
              onPressed: () => unawaited(Future<void>.sync(widget.onLoadMore)),
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

class _DayHeader extends StatelessWidget {
  const new({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
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
          style: BaraedaTypography.label.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
