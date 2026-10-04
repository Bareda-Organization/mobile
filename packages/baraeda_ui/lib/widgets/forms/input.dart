// 원본 `design-system/components/forms/Input.jsx` 대응.
// 원본은 절대위치 아이콘/서픽스를 얹은 손조립 `<input>`이지만, Flutter에서는
// 그 구조를 그대로 옮기지 않고 `TextField` + `InputDecoration`(관례적 구조)을
// 쓴다 — 상태별(enabled/focused/error) 보더만 브랜드 값으로 오버라이드한다.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:baraeda_ui/widgets/core/icon_button.dart';
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
///
/// [obscureText] 인 칸(비밀번호)은 오른쪽에 보기 전환 눈 아이콘이 저절로 붙는다(Ruling 834) — 보임 여부는
/// 칸 안에서 들고 있어 화면이 따로 상태를 두지 않는다. 화면이 [suffix] 를 직접 주면 그쪽이 이긴다.
class BaraedaInput extends StatefulWidget {
  const new({
    super.key,
    this.label,
    this.hint,
    this.placeholder,
    this.error,
    this.icon,
    this.suffix,
    this.required = false,
    this.announceRequired = false,
    this.obscureText = false,
    this.enabled = true,
    this.controller,
    this.onChanged,
    this.keyboardType,
    this.kind = BaraedaInputKind.text,
  });

  final String? label;
  final String? hint;

  /// 칸이 비어 있을 때만 칸 안에 흐리게 보이는 입력 예시(시안 `실명을 입력해 주세요`). 값이 아니라 안내라 [hint] 와 따로
  /// 둔다.
  final String? placeholder;
  final String? error;

  /// 필드 왼쪽 Lucide 아이콘.
  final String? icon;

  /// 필드 오른쪽에 붙는 보조 위젯(단위 텍스트 등).
  final Widget? suffix;

  /// 라벨 옆에 `*`를 눈으로 보이게 붙인다.
  final bool required;

  /// 필수 칸 — 눈에는 아무것도 덧붙이지 않고(시안에 `*` 가 없다) 화면 낭독기만 칸 이름 뒤에 "필수" 를 읽는다
  /// (Ruling 833). [required] 와 따로다.
  final bool announceRequired;

  /// 가려진 입력(비밀번호). 눈 아이콘으로 사용자가 잠시 보이게 바꿀 수 있다.
  final bool obscureText;
  final bool enabled;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;

  /// 입력 종류 — 자동 완성 · 자판 · 철자 교정 속성을 정한다. [keyboardType] 을 따로 주면 그쪽이 이긴다.
  final BaraedaInputKind kind;

  @override
  State<BaraedaInput> createState() => _BaraedaInputState();
}

class _BaraedaInputState extends State<BaraedaInput> {
  /// 눈 아이콘으로 보이게 바꿨는가 — 칸마다 따로다.
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final w = widget;
    final hasError = w.error != null && w.error!.isNotEmpty;
    final attributes = _attributesOf(w.kind);
    final eye = w.obscureText && w.suffix == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (w.label != null) ...[
          _InputLabel(label: w.label!, required: w.required, error: hasError),
          const SizedBox(height: 6),
        ],
        Semantics(
          textField: true,
          label: _readerLabel(w),
          enabled: w.enabled,
          child: TextField(
            controller: w.controller,
            onChanged: w.onChanged,
            enabled: w.enabled,
            obscureText: w.obscureText && !_revealed,
            keyboardType: w.keyboardType ?? attributes.keyboardType,
            autofillHints: attributes.autofillHints,
            autocorrect: attributes.correct,
            enableSuggestions: attributes.correct,
            style: BaraedaTypography.body.copyWith(color: colors.textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: w.enabled ? colors.surfaceCard : colors.bgSubtle,
              // 시안 입력 칸 높이 52.
              constraints: const BoxConstraints(
                minHeight: BaraedaSpacing.inputHeight,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              hintText: w.placeholder,
              hintStyle: BaraedaTypography.body.copyWith(
                color: colors.textTertiary,
              ),
              prefixIcon: w.icon == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(left: 12, right: 8),
                      child: BaraedaIcon(w.icon!, color: colors.textTertiary),
                    ),
              prefixIconConstraints: const BoxConstraints(),
              suffixIcon: eye
                  ? BaraedaIconButton(
                      icon: _revealed ? 'eye-off' : 'eye',
                      label: _revealed ? '비밀번호 숨기기' : '비밀번호 보기',
                      onPressed: () => setState(() => _revealed = !_revealed),
                    )
                  : w.suffix,
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
        if (hasError || (w.hint != null && w.hint!.isNotEmpty)) ...[
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
                    w.error!,
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
              w.hint!,
              style: BaraedaTypography.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
        ],
      ],
    );
  }

  /// 낭독 이름 — 필수 칸이면 칸 이름 뒤에 "필수" 를 붙인다. 눈에 보이는 라벨은 그대로다.
  String? _readerLabel(BaraedaInput w) {
    final label = w.label;
    if (label == null || !w.announceRequired) return label;
    return '$label 필수';
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
