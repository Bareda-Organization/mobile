import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/features/notifications/presentation/notification_providers.dart';

/// 홈 머리말의 [알림] 진입 버튼 — 안 읽은 수(§3.12 `unread_count`)를 배지로 보인다(99 초과는 `99+`).
///
/// 운행 중 화면(운전 화면 · 명단)에는 두지 않는다 — 운전 중 시선을 뺏는 요소를 만들지 않는다(R46).
class NotificationBellButton extends ConsumerWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(
      notificationFeedProvider.select((feed) => feed.value?.unreadCount ?? 0),
    );
    return Badge(
      isLabelVisible: unread > 0,
      backgroundColor: context.colors.statusMissed,
      textColor: context.colors.textInverse,
      label: Text(unread > 99 ? '99+' : '$unread'),
      // 배지 숫자 글자는 낭독하지 않는다 — 버튼 라벨이 건수를 문장으로 말한다.
      child: BaraedaIconButton(
        icon: 'bell',
        label: unread > 0 ? '알림, 안 읽은 알림 $unread건' : '알림',
        onPressed: () => context.push(AppRoutes.notifications),
      ),
    );
  }
}
