import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/ui/failure_message.dart';
import 'package:parent_app/features/home/domain/notification_item.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';

/// §3.12 알림 1페이지를 홈 화면에 압축해 보여준다(§1.8 — 무한 스크롤이
/// 아니라 1페이지). 항목을 누르면 §3.13 로 읽음 처리하고, 종류에 맞는 화면이 있으면 이동한다.
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

    final size = ref.watch(notificationPageSizeProvider);
    return Column(
      children: [
        ...page.items.map((item) => _buildTile(context, ref, item)),
        // F05-08 — 첫 20건 뒤의 알림(특히 확인 못 한 미승차)을 볼 길. 서버 한도(100건)까지 늘린다.
        if (page.hasNext && size < notificationPageMax)
          BaraedaButton(
            label: '더 보기',
            size: BaraedaButtonSize.sm,
            variant: BaraedaButtonVariant.ghost,
            onPressed: () =>
                ref.read(notificationPageSizeProvider.notifier).state =
                    size + notificationPageStep,
          ),
      ],
    );
  }

  Widget _buildTile(
    BuildContext context,
    WidgetRef ref,
    NotificationItem item,
  ) {
    final (status, label) = _tagOf(item.type);
    return NotificationCard(
      status: status,
      statusLabel: label,
      title: item.title,
      sub: item.body,
      meta: item.studentName,
      time: _relativeTime(item.sentAt, now),
      unread: item.isUnread,
      onTap: item.isUnread || _routeOf(item.type) != null
          ? () => _open(context, ref, item)
          : null,
    );
  }

  /// 안 읽은 알림이면 읽음 처리하고, 종류에 맞는 화면이 있으면 그리로 간다(R32 P10).
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    NotificationItem item,
  ) async {
    final route = _routeOf(item.type);
    if (route != null) unawaited(context.push<void>(route));
    if (!item.isUnread) return;
    try {
      await _markRead(ref, item.notificationId);
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

  Future<void> _markRead(WidgetRef ref, String notificationId) async {
    await ref.read(notificationRepositoryProvider).markRead(notificationId);
    ref.invalidate(notificationsProvider);
  }
}

/// 알림 종류(§9.7) → 눌렀을 때 갈 화면. 없으면 읽음 처리만 한다.
/// 운행·승하차·도착·지연은 실시간 지도(UF-P-07), 변경 결과는 일정 화면의 신청 이력(UF-P-06).
String? _routeOf(String type) => switch (type) {
  'boarding' ||
  'alighting' ||
  'boarding_canceled' ||
  'alighting_canceled' ||
  'no_show' ||
  'arrive' ||
  'delay' ||
  'run_started' => AppRoutes.liveMap,
  'change_decided' => AppRoutes.schedule,
  _ => null,
};

/// 알림 종류(§9.7) → 상태 태그. 색 규칙은 `FEATURE_SPEC C-09` —
/// 그린(완료) · 앰버(이동·지연) · 레드(미승차·긴급) · 스톤(대기·종료).
///
/// ⚠ **모르는 종류를 그린으로 떨어뜨리지 않는다.** §9.7 은 앞으로도 늘고,
/// 기본값이 `boarded`(초록 '승차 완료')인 [NotificationCard] 에 그대로 맡기면
/// 새 종류가 생길 때마다 "승차 완료" 로 잘못 표시된다 — 2026-09-21 까지
/// **모든 알림**이 그 상태였다. 특히 `no_show`(미승차)는 버스가 왔는데 아이가
/// 안 나온 사고라, 초록 '승차 완료' 로 보이면 학부모가 사고를 정상으로 읽는다.
(BaraedaStatus, String) _tagOf(String type) => switch (type) {
  'boarding' => (BaraedaStatus.boarded, '승차 완료'),
  'alighting' => (BaraedaStatus.boarded, '하차 완료'),
  'boarding_canceled' => (BaraedaStatus.idle, '승차 취소'),
  'alighting_canceled' => (BaraedaStatus.idle, '하차 취소'),
  'no_show' => (BaraedaStatus.missed, '미승차'),
  'arrive' => (BaraedaStatus.moving, '곧 도착'),
  'delay' => (BaraedaStatus.moving, '지연'),
  'run_started' => (BaraedaStatus.moving, '운행 시작'),
  'change_decided' => (BaraedaStatus.idle, '변경 결과'),
  'signup_decided' => (BaraedaStatus.idle, '가입 결과'),
  _ => (BaraedaStatus.idle, '안내'),
};

String _relativeTime(DateTime sentAt, DateTime now) {
  final diff = now.difference(sentAt);
  if (diff.inMinutes < 1) return '방금 전';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  return '${diff.inDays}일 전';
}
