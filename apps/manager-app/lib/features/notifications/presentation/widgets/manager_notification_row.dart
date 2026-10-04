import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';

/// 매니저 앱 알림 한 줄(시안 `notifications`) — 종류 아이콘 칸 · 제목 + `중요` 칩 ·
/// 본문 · 시각, 오른쪽에 안 읽음 점과
/// 이동 화살표. 안 읽음은 옅은 초록 바탕, 읽음은 흰 바탕이다. 왼쪽 막대는 없다(시안).
///
/// 학부모·학생 앱의 `NotificationTile` 은 같은 패키지를 쓰는 다른 앱이 있어 건드리지 않고 이 앱 안에 둔다.
class ManagerNotificationRow extends StatelessWidget {
  const new({
    required this.icon,
    required this.kindLabel,
    required this.title,
    required this.time,
    required this.timeSpoken,
    super.key,
    this.body,
    this.unread = false,
    this.important = false,
    this.onTap,
  });

  /// 시험이 안 읽음 점을 집는 열쇠.
  static const unreadDotKey = ValueKey<String>('manager-notification-dot');

  /// [BaraedaIcon] 이름.
  final String icon;

  /// 낭독 전용 종류 이름.
  final String kindLabel;
  final String title;
  final String? body;
  final String time;
  final String timeSpoken;
  final bool unread;
  final bool important;

  /// 누르면 할 일(읽음 처리 · 이동). `null` 이면 눌리지 않고 화살표도 없다.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(BaraedaRadius.card);
    final bodyText = body;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Semantics(
        button: onTap != null,
        onTap: onTap,
        label: [
          if (unread) '안 읽음',
          if (important) '중요',
          kindLabel,
          title,
          bodyText,
          timeSpoken,
        ].whereType<String>().join(', '),
        excludeSemantics: true,
        child: Material(
          color: unread ? colors.accentPrimarySoft : colors.surfaceCard,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.all(BaraedaSpacing.space3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceSunken,
                      borderRadius: BorderRadius.circular(
                        BaraedaRadius.control,
                      ),
                    ),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: BaraedaIcon(icon, color: colors.textPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(width: BaraedaSpacing.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              title,
                              style: BaraedaTypography.body.copyWith(
                                color: colors.textPrimary,
                                fontWeight: unread
                                    ? BaraedaFontWeight.bold
                                    : BaraedaFontWeight.medium,
                              ),
                            ),
                            if (important)
                              const BaraedaBadge(
                                label: '중요',
                                tone: BaraedaBadgeTone.amber,
                              ),
                          ],
                        ),
                        if (bodyText != null)
                          WordWrapText(
                            bodyText,
                            style: BaraedaTypography.caption.copyWith(
                              color: colors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          time,
                          style: BaraedaTypography.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (unread)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 8),
                      child: DecoratedBox(
                        key: unreadDotKey,
                        decoration: BoxDecoration(
                          color: colors.accentPrimary,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 8, height: 8),
                      ),
                    ),
                  if (onTap != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: BaraedaIcon(
                        'chevron-right',
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
