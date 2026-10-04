import 'dart:async';

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/button.dart';
import 'package:baraeda_ui/widgets/core/filter_pill.dart';
import 'package:baraeda_ui/widgets/feedback/alert_banner.dart';
import 'package:baraeda_ui/widgets/feedback/empty_state.dart';
import 'package:baraeda_ui/widgets/feedback/notification_time.dart';
import 'package:baraeda_ui/widgets/feedback/skeleton.dart';
import 'package:baraeda_ui/widgets/forms/segmented_control.dart';
import 'package:flutter/material.dart';

/// 스크롤이 끝에서 이만큼(px) 안으로 들어오면 다음 쪽을 미리 받는다.
const double _loadMoreExtent = 300;

/// 걸러 보기와 빈 · 오류 · 불러오는 화면의 모양.
enum NotificationListStyle {
  /// `[전체] | [안 읽음]` 두 칸 전환 + 한 줄 안내(기본 — 매니저 앱).
  segmented,

  /// `[전체]` `[안 읽음 N]` 두 알약 + 큰 그림의 빈 · 오류 화면 + 목록 모양 뼈대(시안 학부모·학생
  /// `notifications*`).
  pills;

  /// 날짜 머리가 오른쪽에 날짜(`10월 3일 (토)`)를 그리는가 — 알약 모양만 그린다.
  bool get headerShowsDate => this == pills;

  /// 알림 행 오른쪽의 시각(Ruling 835) — 머리에 날짜가 있으면 시각만(날짜를 두 번 쓰지 않는다), 없으면 오늘이
  /// 아닌 알림에 날짜를 붙인다. 화면은 목록에 준 모양으로 행 시각도 이 메서드로 그린다.
  String rowTime(DateTime sentAt, DateTime now) =>
      headerShowsDate ? clockLabel(sentAt) : timeLabel(sentAt, now);
}

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
    this.style = NotificationListStyle.segmented,
    this.unreadCount = 0,
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

  /// 걸러 보기 · 빈 · 오류 · 불러오는 화면의 모양. 기본은 [NotificationListStyle.segmented].
  final NotificationListStyle style;

  /// 서버가 세는 안 읽은 수(§3.12 `unread_count`) — [NotificationListStyle.pills] 의 `안
  /// 읽음 N` 에 쓴다.
  final int unreadCount;

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
          child: w.style == NotificationListStyle.pills
              ? Row(
                  children: [
                    BaraedaFilterPill(
                      label: '전체',
                      selected: !w.unreadOnly,
                      onTap: () => w.onUnreadOnlyChanged(false),
                    ),
                    const SizedBox(width: BaraedaSpacing.space2),
                    BaraedaFilterPill(
                      label: '안 읽음 ${w.unreadCount}',
                      selected: w.unreadOnly,
                      onTap: () => w.onUnreadOnlyChanged(true),
                    ),
                  ],
                )
              : BaraedaSegmentedControl(
                  block: true,
                  options: const [
                    BaraedaSegmentedOption('all', label: '전체'),
                    BaraedaSegmentedOption('unread', label: '안 읽음'),
                  ],
                  value: w.unreadOnly ? 'unread' : 'all',
                  onChanged: (value) =>
                      w.onUnreadOnlyChanged(value == 'unread'),
                ),
        ),
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final w = widget;
    final pills = w.style == NotificationListStyle.pills;
    if (w.isLoading) {
      return pills
          ? const _SkeletonBody()
          : const Center(child: CircularProgressIndicator());
    }
    final onRetry = w.onRetry;
    if (onRetry != null && pills) {
      return ListView(
        children: [
          EmptyState(
            icon: 'wifi-off',
            title: '알림을 불러오지 못했어요',
            body: '인터넷 연결을 확인하고 다시 시도해 주세요. 새 알림은 푸시로는 계속 와요.',
            action: BaraedaButton(
              label: '다시 시도',
              icon: 'refresh',
              onPressed: onRetry,
            ),
          ),
        ],
      );
    }
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
                if (pills)
                  EmptyState(
                    icon: w.unreadOnly ? 'circle-check' : 'bell',
                    title: w.unreadOnly ? '안 읽은 알림이 없어요' : '새 알림이 없어요',
                    body: w.unreadOnly
                        ? '모두 확인했어요. 새 알림은 푸시로도 알려 드려요.'
                        : '최근 14일 동안 받은 알림이 여기에 모여요.',
                    action: w.unreadOnly
                        ? BaraedaButton(
                            label: '전체 알림 보기',
                            variant: BaraedaButtonVariant.secondary,
                            onPressed: () => w.onUnreadOnlyChanged(false),
                          )
                        : null,
                  )
                else
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

  /// 날짜 머리와 한 날의 행을 묶은 카드를 한 줄씩 만드는 빌더 목록(Ruling 835 — 걸러 보기 모양과 무관하게
  /// 한 날의 알림은 카드 하나다).
  List<Widget Function()> _rows() {
    final w = widget;
    final rows = <Widget Function()>[];
    String? lastHeader;
    var group = <T>[];

    void flushGroup() {
      if (group.isEmpty) return;
      final items = group;
      rows.add(
        () => _DayCard(
          children: [for (final item in items) w.itemBuilder(context, item)],
        ),
      );
      group = <T>[];
    }

    for (final item in w.items) {
      final sentAt = w.sentAtOf(item);
      final header = dayHeader(sentAt, w.now);
      if (header != lastHeader) {
        flushGroup();
        final date = w.style.headerShowsDate
            ? dayHeaderDate(sentAt, w.now)
            : null;
        rows.add(() => _DayHeader(label: header, date: date));
        lastHeader = header;
      }
      group.add(item);
    }
    flushGroup();
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
  const new({required this.label, this.date});

  final String label;

  /// 머리 오른쪽의 날짜(`10월 3일 (토)`) — 없으면 머리만.
  final String? date;

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
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: BaraedaTypography.label.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ),
            if (date != null)
              Text(
                date!,
                style: BaraedaTypography.caption.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 한 날의 알림 행을 묶는 흰 카드 — 행 사이에 가는 선.
class _DayCard extends StatelessWidget {
  const new({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(BaraedaRadius.card);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaraedaSpacing.gutterMobile,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          borderRadius: radius,
          border: Border.all(color: colors.borderSubtle),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: 1, color: colors.borderSubtle),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 불러오는 중 뼈대 — 날짜 머리 자리 + 알림 행 모양 네 줄(시안 `notifications--loading`).
class _SkeletonBody extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: '알림을 불러오는 중',
      child: const ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            BaraedaSpacing.gutterMobile,
            BaraedaSpacing.space4,
            BaraedaSpacing.gutterMobile,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BaraedaSkeleton(width: 40),
              SizedBox(height: BaraedaSpacing.space3),
              BaraedaSkeletonList(count: 4),
            ],
          ),
        ),
      ),
    );
  }
}
