// 비상 버튼 3형태 — 머리줄 알약 · 떠 있는 둥근 단추 · 긴 단추(시안 `.m-sos`).
// 기사 · 동승자 화면 머리줄에는 항상 둔다.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/button.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:baraeda_ui/widgets/core/pressable.dart';
import 'package:flutter/material.dart';

/// 비상 버튼의 모양.
enum BaraedaSosForm {
  /// 머리줄 오른쪽 알약 — `⚠ 비상`.
  header,

  /// 지도 위에 떠 있는 64×64 둥근 단추(아이콘만).
  floating,

  /// 비상 화면 맨 아래 긴 단추 — `⚠ 비상 알림 보내기`.
  wide,
}

/// 위험 면(빨강) 비상 버튼. 낭독은 [label] 을 읽는다.
class BaraedaSosButton extends StatelessWidget {
  const new({
    super.key,
    this.form = BaraedaSosForm.header,
    this.label,
    this.onPressed,
  });

  final BaraedaSosForm form;

  /// 비우면 모양에 맞는 기본 문구(`비상` · `비상 알림 보내기`).
  final String? label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    switch (form) {
      case BaraedaSosForm.wide:
        return BaraedaButton(
          label: label ?? '비상 알림 보내기',
          variant: BaraedaButtonVariant.danger,
          icon: 'triangle-alert',
          block: true,
          onPressed: onPressed,
        );
      case BaraedaSosForm.header:
        const radius = BorderRadius.all(Radius.circular(BaraedaRadius.pill));
        return BaraedaPressable(
          onTap: onPressed,
          borderRadius: radius,
          scale: 0.96,
          semanticLabel: label ?? '비상',
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.dangerSolid,
              borderRadius: radius,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: BaraedaSpacing.tap),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BaraedaIcon('triangle-alert', color: colors.onDangerSolid),
                    const SizedBox(width: 6),
                    Text(
                      label ?? '비상',
                      style: BaraedaTypography.body.copyWith(
                        color: colors.onDangerSolid,
                        fontWeight: BaraedaFontWeight.bold,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      case BaraedaSosForm.floating:
        return BaraedaPressable(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(BaraedaRadius.pill),
          scale: 0.96,
          semanticLabel: label ?? '비상',
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.dangerSolid,
              shape: BoxShape.circle,
              boxShadow: BaraedaShadows.raisedLight,
            ),
            child: SizedBox(
              width: 64,
              height: 64,
              child: Center(
                child: BaraedaIcon(
                  'triangle-alert',
                  size: 28,
                  color: colors.onDangerSolid,
                ),
              ),
            ),
          ),
        );
    }
  }
}
