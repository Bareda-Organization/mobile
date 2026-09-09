// 원본 `design-system/components/forms/SegmentedControl.jsx` 대응.
//
// Flutter 내장 위젯 중 이 알약형 트랙 선택자와 정확히 맞는 것이 없다
// (`SegmentedButton`은 Material 3 스타일 사각 세그먼트라 radius·배경이
// 브랜드와 다르고, 겹쳐 쓰면 오버라이드가 커스텀 구현보다 더 늘어난다).
// 그래서 `role=tablist/tab` 시맨틱만 원본과 맞추고 나머지는 완전히
// 새로 그린다 — `Row` 안에 알약 버튼을 늘어놓고 선택된 항목만 배경을 채운다.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:flutter/material.dart';

/// [BaraedaSegmentedControl]의 선택지 하나.
class BaraedaSegmentedOption {
  const BaraedaSegmentedOption(this.value, {String? label})
    : label = label ?? value;

  final String value;
  final String label;
}

/// 탭처럼 동작하는 세그먼트 선택자(예: "전체 · 승차 · 하차").
class BaraedaSegmentedControl extends StatelessWidget {
  const BaraedaSegmentedControl({
    required this.options,
    required this.value,
    super.key,
    this.onChanged,
    this.block = false,
  });

  final List<BaraedaSegmentedOption> options;
  final String value;
  final ValueChanged<String>? onChanged;

  /// 가로 100%로 균등 분할.
  final bool block;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: colors.bgSubtle,
          borderRadius: BorderRadius.circular(BaraedaRadius.pill),
        ),
        child: Row(
          mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
          children: [
            for (final option in options)
              _SegmentedButton(
                option: option,
                selected: option.value == value,
                expand: block,
                colors: colors,
                onSelected: onChanged == null
                    ? null
                    : () => onChanged!(option.value),
              ),
          ],
        ),
      ),
    );
  }
}

class _SegmentedButton extends StatelessWidget {
  const _SegmentedButton({
    required this.option,
    required this.selected,
    required this.expand,
    required this.colors,
    required this.onSelected,
  });

  final BaraedaSegmentedOption option;
  final bool selected;
  final bool expand;
  final BaraedaColors colors;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      selected: selected,
      button: true,
      label: option.label,
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(BaraedaRadius.pill),
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        hoverColor: Colors.black.withValues(alpha: 0.04),
        focusColor: colors.focusRing.withValues(alpha: 0.32),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? colors.surfaceCard : Colors.transparent,
            borderRadius: BorderRadius.circular(BaraedaRadius.pill),
            boxShadow: selected ? BaraedaShadows.smLight : const [],
          ),
          child: Text(
            option.label,
            textAlign: TextAlign.center,
            style: BaraedaTypography.labelSm.copyWith(
              color: selected ? colors.textPrimary : colors.textTertiary,
            ),
          ),
        ),
      ),
    );

    return expand ? Expanded(child: button) : button;
  }
}
