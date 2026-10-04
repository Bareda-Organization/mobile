import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';

/// [InfoRowsCard] 한 줄 — 이름(왼쪽 고정 폭)과 값. [value] 대신 [valueWidget] 을 줄 수 있다(칩 등).
class InfoRow {
  const new(this.label, {this.value, this.valueWidget})
    : assert(
        (value == null) != (valueWidget == null),
        'value 와 valueWidget 중 하나만 준다',
      );

  final String label;
  final String? value;
  final Widget? valueWidget;
}

/// `지연 시간 | 10분` 처럼 이름 · 값 줄을 선으로 나눈 카드(시안 `delay--sent` · `emergency` 의 정보 표).
class InfoRowsCard extends StatelessWidget {
  const new({required this.rows, super.key});

  final List<InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BaraedaCard(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: colors.borderSubtle),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(
                      rows[i].label,
                      style: BaraedaTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child:
                        rows[i].valueWidget ??
                        Text(
                          rows[i].value!,
                          style: BaraedaTypography.body.copyWith(
                            color: colors.textPrimary,
                            fontWeight: BaraedaFontWeight.medium,
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
