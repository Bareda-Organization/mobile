// 원본 `design-system/components/forms/Checkbox.jsx` 대응.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:flutter/material.dart';

/// 체크박스 + 라벨 한 줄.
///
/// [onChanged]가 null이면 [disabled]와 무관하게 비활성으로 렌더링한다
/// (Flutter 관례 — 콜백 부재가 곧 비활성).
class BaraedaCheckbox extends StatelessWidget {
  const BaraedaCheckbox({
    required this.checked,
    required this.label,
    super.key,
    this.sublabel,
    this.onChanged,
    this.disabled = false,
  });

  final bool checked;
  final String label;

  /// 라벨 아래 보조 설명(작은 회색 글자).
  final String? sublabel;
  final ValueChanged<bool>? onChanged;
  final bool disabled;

  bool get _effectivelyDisabled => disabled || onChanged == null;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      checked: checked,
      enabled: !_effectivelyDisabled,
      label: label,
      child: Opacity(
        opacity: _effectivelyDisabled ? 0.42 : 1,
        child: InkWell(
          onTap: _effectivelyDisabled ? null : () => onChanged!(!checked),
          borderRadius: BorderRadius.circular(BaraedaRadius.sm),
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          hoverColor: Colors.black.withValues(alpha: 0.04),
          focusColor: colors.focusRing.withValues(alpha: 0.32),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CheckboxBox(checked: checked, colors: colors),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: BaraedaTypography.body.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      if (sublabel != null)
                        Text(
                          sublabel!,
                          style: BaraedaTypography.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckboxBox extends StatelessWidget {
  const _CheckboxBox({required this.checked, required this.colors});

  final bool checked;
  final BaraedaColors colors;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: checked ? colors.accentPrimary : colors.surfaceCard,
        border: checked ? null : Border.all(color: colors.borderStrong),
        borderRadius: BorderRadius.circular(BaraedaRadius.xs),
      ),
      child: checked
          ? Icon(Icons.check, size: 14, color: colors.textInverse)
          : null,
    );
  }
}
