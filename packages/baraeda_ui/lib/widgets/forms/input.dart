// 원본 `design-system/components/forms/Input.jsx` 대응.
// 원본은 절대위치 아이콘/서픽스를 얹은 손조립 `<input>`이지만, Flutter에서는
// 그 구조를 그대로 옮기지 않고 `TextField` + `InputDecoration`(관례적 구조)을
// 쓴다 — 상태별(enabled/focused/error) 보더만 브랜드 값으로 오버라이드한다.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:baraeda_ui/widgets/core/word_wrap_text.dart';
import 'package:flutter/material.dart';

/// 바래다 기본 텍스트 입력.
///
/// [label]이 있으면 필드 위에, [hint]는 라벨 아래 보조 설명으로, [error]가
/// 있으면 hint 대신 레드로 노출된다(둘 다 동시에 보이지 않는다).
class BaraedaInput extends StatelessWidget {
  const new({
    super.key,
    this.label,
    this.hint,
    this.error,
    this.icon,
    this.suffix,
    this.required = false,
    this.obscureText = false,
    this.enabled = true,
    this.controller,
    this.onChanged,
    this.keyboardType,
  });

  final String? label;
  final String? hint;
  final String? error;

  /// 필드 왼쪽 Lucide 아이콘.
  final String? icon;

  /// 필드 오른쪽에 붙는 보조 위젯(단위 텍스트 등).
  final Widget? suffix;

  /// 라벨 옆에 `*`를 붙인다.
  final bool required;
  final bool obscureText;
  final bool enabled;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasError = error != null && error!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          _InputLabel(label: label!, required: required),
          const SizedBox(height: 6),
        ],
        Semantics(
          textField: true,
          label: label,
          enabled: enabled,
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            enabled: enabled,
            obscureText: obscureText,
            keyboardType: keyboardType,
            style: BaraedaTypography.body.copyWith(color: colors.textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: enabled ? colors.surfaceCard : colors.bgSubtle,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              prefixIcon: icon == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(left: 12, right: 8),
                      child: BaraedaIcon(icon!, color: colors.textTertiary),
                    ),
              prefixIconConstraints: const BoxConstraints(),
              suffixIcon: suffix,
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

class _InputLabel extends StatelessWidget {
  const new({required this.label, required this.required});

  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return RichText(
      text: TextSpan(
        style: BaraedaTypography.label.copyWith(color: colors.textPrimary),
        children: [
          TextSpan(text: label),
          if (required)
            TextSpan(
              text: ' *',
              style: TextStyle(color: colors.statusMissed),
            ),
        ],
      ),
    );
  }
}
