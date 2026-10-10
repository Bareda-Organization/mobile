import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 급할 때 거는 학원 전화 — 번호를 줄 때만 나온다(`Ruling 827`). 못 불러온 화면(홈 전체 · 버스 위치)에서도 버스가
/// 궁금한 사람이 갈 곳이 있다.
class AcademyPhoneCard extends StatelessWidget {
  const new({required this.phone, super.key});

  final String phone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return BaraedaCard(
      tone: BaraedaCardTone.mist,
      child: Row(
        children: [
          ExcludeSemantics(
            child: BaraedaIcon('phone', color: colors.accentPrimary),
          ),
          const SizedBox(width: BaraedaSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const WordWrapText(
                  '버스가 급하게 궁금하면',
                  style: TextStyle(fontWeight: BaraedaFontWeight.bold),
                ),
                WordWrapText(
                  '학원 $phone',
                  style: BaraedaTypography.bodySm.copyWith(
                    color: colors.accentPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: BaraedaSpacing.space2),
          BaraedaButton(
            label: '전화',
            size: BaraedaButtonSize.sm,
            variant: BaraedaButtonVariant.secondary,
            onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
          ),
        ],
      ),
    );
  }
}
