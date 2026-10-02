// 원본 `design-system/components/forms/CodeInput.jsx` 대응.
//
// 원본은 실제 `<input>`을 투명하게 만들어 보이는 박스 UI 위에 절대위치로
// 겹쳐 두고, 키 입력은 그 투명 input이 받는 "보이지 않는 진짜 입력 위에
// 보이는 장식을 겹치는" 기법을 쓴다. 이 위젯은 `Stack` + `Positioned.fill`
// + `Opacity(0)`로 그 구조를 그대로 옮긴다 — Flutter에서도 유효하고 깨끗한
// 번역이라 판단했다. 포커스 여부로 현재 칸을 하이라이트해야 해서
// `FocusNode`(위젯 생명주기에 묶인 상태)가 필요해 `StatefulWidget`이다.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/word_wrap_text.dart';
import 'package:baraeda_ui/widgets/forms/code_input_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 인증번호 등 고정 길이 코드 입력. 입력값은 자동으로 대문자로 바뀐다.
class BaraedaCodeInput extends StatefulWidget {
  const new({
    required this.value,
    required this.onChanged,
    super.key,
    this.length = 6,
    this.label,
    this.hint,
    this.error,
  });

  final String value;
  final ValueChanged<String> onChanged;

  /// 칸 수. 원본 기본값 6.
  final int length;
  final String? label;
  final String? hint;
  final String? error;

  @override
  State<BaraedaCodeInput> createState() => _BaraedaCodeInputState();
}

class _BaraedaCodeInputState extends State<BaraedaCodeInput> {
  final FocusNode _focusNode = FocusNode();
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(BaraedaCodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  void _handleFocusChange() => setState(() {});

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasError = widget.error != null && widget.error!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: BaraedaTypography.label.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 6),
        ],
        Semantics(
          textField: true,
          label: widget.label,
          child: SizedBox(
            height: 52,
            child: Stack(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < widget.length; i++)
                      BaraedaCodeInputBox(
                        char: i < widget.value.length ? widget.value[i] : '',
                        active: _focusNode.hasFocus && i == widget.value.length,
                        hasError: hasError,
                      ),
                  ],
                ),
                Positioned.fill(
                  child: Opacity(
                    opacity: 0,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      maxLength: widget.length,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp('[a-zA-Z0-9]'),
                        ),
                        BaraedaUpperCaseTextFormatter(),
                      ],
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                      ),
                      onChanged: widget.onChanged,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasError || (widget.hint != null && widget.hint!.isNotEmpty)) ...[
          const SizedBox(height: 6),
          WordWrapText(
            hasError ? widget.error! : widget.hint!,
            style: BaraedaTypography.caption.copyWith(
              color: hasError ? colors.statusMissed : colors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}
