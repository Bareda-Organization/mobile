// 제출 영수증 — 방금 낸 신청의 내용을 그대로 다시 보여 준다(시안 P1 `daily-change--done`).
// 위쪽 3px 초록 선 + `✓ 제목` + 이름 · 값 줄들.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/card.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:flutter/material.dart';

/// 영수증 한 줄 — 이름(왼쪽, 84 폭)과 값.
class BaraedaReceiptRow {
  const new(this.label, this.value);

  final String label;
  final String value;
}

/// 제출한 내용의 영수증 카드. 쓰던 양식 조각을 남겨 두면 또 눌러도 되는 화면처럼 보여서,
/// 제출 뒤에는 이 카드로 바꾼다.
class BaraedaReceiptCard extends StatelessWidget {
  const new({required this.title, required this.rows, super.key});

  final String title;
  final List<BaraedaReceiptRow> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      container: true,
      child: BaraedaCard(
        highlight: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.statusBoardedSoft,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Center(
                      child: BaraedaIcon(
                        'check',
                        size: 16,
                        color: colors.statusBoarded,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: BaraedaSpacing.space3),
                Expanded(
                  child: Text(
                    title,
                    style: BaraedaTypography.title.copyWith(
                      color: colors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: BaraedaSpacing.space3),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    SizedBox(
                      width: 84,
                      child: Text(
                        row.label,
                        style: BaraedaTypography.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.value,
                        style: BaraedaTypography.body.copyWith(
                          color: colors.textPrimary,
                          fontWeight: BaraedaFontWeight.medium,
                          height: 1.35,
                        ),
                      ),
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
