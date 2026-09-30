// 도착 지연 시간 선택 — 기사·동승자 앱 공통, 5분 단위 고정.
// 원본: `frontend/design-system/components/transit/DelayPicker.jsx`.
//
// 자유 입력이 아니라 5분 단위 선택만 허용한다(카피/정책 규칙 — 확정 전 자유
// 텍스트 입력 금지).

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:flutter/material.dart';

const List<int> _defaultDelayOptions = [5, 10, 15, 20, 25, 30];

/// 지연 시간 선택 — 3열 그리드, 항목 수가 고정([options])이라 [GridView] 대신
/// [Wrap] 으로 구성한다(항목 수가 적어 셀 크기 계산 오버헤드가 불필요).
class DelayPicker extends StatelessWidget {
  const DelayPicker({
    super.key,
    this.value,
    this.onChanged,
    this.options = _defaultDelayOptions,
  });

  final int? value;
  final ValueChanged<int>? onChanged;

  /// 분 단위 후보값. 기본 [5, 10, 15, 20, 25, 30].
  final List<int> options;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            '지연 시간 · 5분 단위',
            style: BaraedaTypography.labelSm.copyWith(
              height: 1.2,
              color: colors.textSecondary,
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            const columns = 3;
            const gap = BaraedaSpacing.space2;
            final cellWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final minutes in options)
                  SizedBox(
                    width: cellWidth,
                    child: _DelayOption(
                      minutes: minutes,
                      selected: minutes == value,
                      onTap: onChanged == null
                          ? null
                          : () => onChanged!(minutes),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DelayOption extends StatelessWidget {
  const _DelayOption({
    required this.minutes,
    required this.selected,
    required this.onTap,
  });

  final int minutes;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = selected ? colors.statusMoving : colors.textPrimary;
    final background = selected ? colors.statusMovingSoft : colors.surfaceCard;
    final border = selected ? colors.statusMoving : colors.borderControl;

    return Semantics(
      button: true,
      selected: selected,
      label: '$minutes분',
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(BaraedaRadius.control),
        child: InkWell(
          onTap: onTap,
          focusColor: colors.focusRing.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(BaraedaRadius.control),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BaraedaRadius.control),
              border: Border.all(color: border),
            ),
            child: Text(
              '$minutes분',
              style: BaraedaTypography.body.copyWith(
                height: 1,
                fontWeight: BaraedaFontWeight.bold,
                color: tint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
