// 원본 `design-system/components/forms/Select.jsx` 대응.
//
// `DropdownButtonFormField`의 맨 기본값을 그대로 쓰면 파란 하이라이트·직각
// 팝업 등 Material 기본 룩이 그대로 노출돼 브랜드 규칙(색·radius·shadow)이
// 깨진다. 그래서 `InputDecoration`으로 필드 자체를, `dropdownColor`·
// `borderRadius`·`menuMaxHeight`로 펼침 메뉴를 전부 오버라이드해 [BaraedaInput]과
// 같은 톤으로 맞춘다. 완전 커스텀 팝업(오버레이 직접 관리)도 검토했으나,
// `DropdownButtonFormField`가 이미 포커스·키보드 탐색·스크린 리더 지원을
// 갖추고 있어 그 이점을 버릴 이유가 없다고 판단했다.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:flutter/material.dart';

/// [BaraedaSelect]의 선택지 하나. 원본의 `string[] | {value,label}[]` 두
/// 형태를 이 클래스 하나로 흡수한다 — 문자열만 있으면 `value == label`.
class BaraedaSelectOption {
  const BaraedaSelectOption(this.value, {String? label})
    : label = label ?? value;

  factory BaraedaSelectOption.fromLabel(String label) =>
      BaraedaSelectOption(label);

  final String value;
  final String label;
}

/// 드롭다운 선택 필드.
class BaraedaSelect extends StatelessWidget {
  const BaraedaSelect({
    required this.options,
    super.key,
    this.label,
    this.hint,
    this.error,
    this.value,
    this.onChanged,
    this.enabled = true,
  });

  final String? label;
  final String? hint;
  final String? error;
  final List<BaraedaSelectOption> options;
  final String? value;
  final ValueChanged<String?>? onChanged;
  final bool enabled;

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
          label: label,
          enabled: enabled,
          child: DropdownButtonFormField<String>(
            initialValue: value,
            onChanged: enabled ? onChanged : null,
            icon: Icon(Icons.expand_more, color: colors.textTertiary, size: 20),
            dropdownColor: colors.surfaceCard,
            borderRadius: BorderRadius.circular(BaraedaRadius.control),
            style: BaraedaTypography.body.copyWith(color: colors.textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: enabled ? colors.surfaceCard : colors.bgSubtle,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
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
            items: [
              for (final option in options)
                DropdownMenuItem(
                  value: option.value,
                  child: Text(option.label),
                ),
            ],
          ),
        ),
        if (hasError || (hint != null && hint!.isNotEmpty)) ...[
          const SizedBox(height: 6),
          Text(
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
