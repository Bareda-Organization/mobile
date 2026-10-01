// 원본 `design-system/components/forms/Textarea.jsx` 대응.
// 원본과 동일하게 `required` prop이 없다(자유 서술 필드는 필수 표시를 두지
// 않는다는 것이 원본의 의도적 선택).

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/word_wrap_text.dart';
import 'package:flutter/material.dart';

/// 여러 줄 텍스트 입력.
class BaraedaTextarea extends StatelessWidget {
  const BaraedaTextarea({
    super.key,
    this.label,
    this.hint,
    this.error,
    this.rows = 4,
    this.enabled = true,
    this.controller,
    this.onChanged,
  });

  final String? label;
  final String? hint;
  final String? error;

  /// 보이는 줄 수. 원본 기본값 4.
  final int rows;
  final bool enabled;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasError = error != null && error!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: BaraedaTypography.label.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 6),
        ],
        Semantics(
          textField: true,
          label: label,
          enabled: enabled,
          multiline: true,
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            enabled: enabled,
            maxLines: rows,
            style: BaraedaTypography.body.copyWith(color: colors.textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: enabled ? colors.surfaceCard : colors.bgSubtle,
              contentPadding: const EdgeInsets.all(14),
              border: _borderFor(colors.borderControl),
              enabledBorder: _borderFor(
                hasError ? colors.statusMissed : colors.borderControl,
              ),
              focusedBorder: _borderFor(
                hasError ? colors.statusMissed : colors.accentPrimary,
                width: BaraedaBorderWidth.strong,
              ),
              disabledBorder: _borderFor(colors.borderSubtle),
            ),
          ),
        ),
        if (hasError || (hint != null && hint!.isNotEmpty)) ...[
          const SizedBox(height: 6),
          WordWrapText(
            hasError ? error! : hint!,
            style: BaraedaTypography.caption.copyWith(
              color: hasError ? colors.statusMissed : colors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}

OutlineInputBorder _borderFor(Color color, {double width = 1}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(BaraedaRadius.control),
    borderSide: BorderSide(color: color, width: width),
  );
}
