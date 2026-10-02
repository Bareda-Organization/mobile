// 화면 상단 상황 안내 배너 — 지연·미탑승처럼 지금 알아야 하는 사실을 결론부터 보여준다.
// 원본: `frontend/design-system/components/feedback/AlertBanner.jsx`.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:baraeda_ui/widgets/core/word_wrap_text.dart';
import 'package:flutter/material.dart';

/// 배너의 상태 컬러 — `readme.md` 상태 컬러 규칙을 그대로 따른다.
enum AlertTone { info, moving, missed, boarded }

/// [AlertTone] 별 아이콘·전경/배경 색을 테마에서 뽑아 주는 헬퍼.
class _AlertToneStyle {
  const new({
    required this.icon,
    required this.foreground,
    required this.background,
  });

  factory of(BuildContext context, AlertTone tone) {
    final colors = context.colors;
    return switch (tone) {
      AlertTone.info => _AlertToneStyle(
        icon: 'info',
        foreground: colors.textBrand,
        background: colors.accentPrimarySoft,
      ),
      AlertTone.moving => _AlertToneStyle(
        icon: 'bus',
        foreground: colors.statusMoving,
        background: colors.statusMovingSoft,
      ),
      AlertTone.missed => _AlertToneStyle(
        icon: 'triangle-alert',
        foreground: colors.statusMissed,
        background: colors.statusMissedSoft,
      ),
      AlertTone.boarded => _AlertToneStyle(
        icon: 'circle-check',
        foreground: colors.statusBoarded,
        background: colors.statusBoardedSoft,
      ),
    };
  }

  final String icon;
  final Color foreground;
  final Color background;
}

/// 화면 상단 상황 안내 배너. 느낌표·이모지는 쓰지 않는다(카피 규칙).
class AlertBanner extends StatelessWidget {
  const new({
    required this.tone,
    super.key,
    this.title,
    this.body,
    this.action,
  });

  /// 상태 컬러 규칙을 그대로 따른다.
  final AlertTone tone;

  /// 결론 한 줄.
  final String? title;

  /// 상세 설명. React 쪽 `children`에 대응.
  final String? body;

  /// 하단 버튼 영역 — 문제 상황이면 다음 행동을 함께 둔다.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final style = _AlertToneStyle.of(context, tone);
    // 제목·본문·버튼을 자식이 각자 읽는다 — 라벨을 또 얹으면 제목이 두 번 읽힌다(F07-10).
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: BaraedaSpacing.space4,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: ExcludeSemantics(
                child: BaraedaIcon(
                  style.icon,
                  size: 18,
                  color: style.foreground,
                ),
              ),
            ),
            const SizedBox(width: BaraedaSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    WordWrapText(
                      title!,
                      style: BaraedaTypography.labelSm.copyWith(
                        fontWeight: BaraedaFontWeight.bold,
                        color: style.foreground,
                      ),
                    ),
                  if (body != null)
                    Padding(
                      padding: EdgeInsets.only(top: title != null ? 4 : 0),
                      child: WordWrapText(
                        body!,
                        style: BaraedaTypography.bodySm.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                  if (action != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: action,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
