// 원본 `design-system/components/forms/Input.jsx` 대응.
// 원본은 절대위치 아이콘/서픽스를 얹은 손조립 `<input>`이지만, Flutter에서는
// 그 구조를 그대로 옮기지 않고 `TextField` + `InputDecoration`(관례적 구조)을
// 쓴다 — 상태별(enabled/focused/error) 보더만 브랜드 값으로 오버라이드한다.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:baraeda_ui/widgets/core/word_wrap_text.dart';
import 'package:flutter/material.dart';

/// 입력 칸의 종류 — 종류마다 자동 완성 · 자판 · 철자 교정 속성이 정해진다(시안 C4).
enum BaraedaInputKind {
  /// 일반 글자.
  text,

  /// 아이디 — 자동 완성 `username`, 철자 교정 · 단어 추천 끔.
  username,

  /// 로그인 비밀번호 — `password`.
  currentPassword,

  /// 새 비밀번호 — `newPassword`.
  newPassword,

  /// 연락처 — 전화 자판 + `telephoneNumber`.
  phone,

  /// 인증번호 — 숫자 자판 + `oneTimeCode`(문자 인증 번호 자동 채움).
  oneTimeCode,
}

class _InputAttributes {
  const new({this.keyboardType, this.autofillHints, this.correct = true});

  final TextInputType? keyboardType;
  final List<String>? autofillHints;

  /// false 면 철자 교정 · 단어 추천을 끈다.
  final bool correct;
}

_InputAttributes _attributesOf(BaraedaInputKind kind) => switch (kind) {
  BaraedaInputKind.text => const _InputAttributes(),
  BaraedaInputKind.username => const _InputAttributes(
    autofillHints: [AutofillHints.username],
    correct: false,
  ),
  BaraedaInputKind.currentPassword => const _InputAttributes(
    autofillHints: [AutofillHints.password],
    correct: false,
  ),
  BaraedaInputKind.newPassword => const _InputAttributes(
    autofillHints: [AutofillHints.newPassword],
    correct: false,
  ),
  BaraedaInputKind.phone => const _InputAttributes(
    keyboardType: TextInputType.phone,
    autofillHints: [AutofillHints.telephoneNumber],
  ),
  BaraedaInputKind.oneTimeCode => const _InputAttributes(
    keyboardType: TextInputType.number,
    autofillHints: [AutofillHints.oneTimeCode],
    correct: false,
  ),
};

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
    this.kind = BaraedaInputKind.text,
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

  /// 입력 종류 — 자동 완성 · 자판 · 철자 교정 속성을 정한다. [keyboardType] 을 따로 주면 그쪽이 이긴다.
  final BaraedaInputKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasError = error != null && error!.isNotEmpty;
    final attributes = _attributesOf(kind);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          _InputLabel(label: label!, required: required, error: hasError),
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
            keyboardType: keyboardType ?? attributes.keyboardType,
            autofillHints: attributes.autofillHints,
            autocorrect: attributes.correct,
            enableSuggestions: attributes.correct,
            style: BaraedaTypography.body.copyWith(color: colors.textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: enabled ? colors.surfaceCard : colors.bgSubtle,
              // 시안 입력 칸 높이 52.
              constraints: const BoxConstraints(
                minHeight: BaraedaSpacing.inputHeight,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              hintStyle: BaraedaTypography.body.copyWith(
                color: colors.textTertiary,
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
              // 오류는 위험 면 색 2px 테두리(시안 `.m-field.err`).
              enabledBorder: hasError
                  ? _borderFor(
                      colors.dangerSolid,
                      width: BaraedaBorderWidth.strong,
                    )
                  : _borderFor(colors.borderControl),
              focusedBorder: _borderFor(
                hasError ? colors.dangerSolid : colors.accentPrimary,
                width: BaraedaBorderWidth.strong,
              ),
              disabledBorder: _borderFor(colors.borderSubtle),
            ),
          ),
        ),
        if (hasError || (hint != null && hint!.isNotEmpty)) ...[
          const SizedBox(height: 6),
          if (hasError)
            // 색만으로 오류를 알리지 않는다 — 경고 아이콘을 앞에 둔다(시안 `.m-err`).
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: BaraedaIcon(
                    'triangle-alert',
                    size: 16,
                    color: colors.statusMissed,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: WordWrapText(
                    error!,
                    style: BaraedaTypography.caption.copyWith(
                      color: colors.statusMissed,
                      fontWeight: BaraedaFontWeight.medium,
                    ),
                  ),
                ),
              ],
            )
          else
            WordWrapText(
              hint!,
              style: BaraedaTypography.caption.copyWith(
                color: colors.textSecondary,
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
  const new({required this.label, required this.required, required this.error});

  final String label;
  final bool required;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return RichText(
      text: TextSpan(
        style: BaraedaTypography.label.copyWith(
          color: error ? colors.statusMissed : colors.textPrimary,
          fontWeight: BaraedaFontWeight.medium,
        ),
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
