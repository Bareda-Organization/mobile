// `code_input.dart`의 보조 위젯 — 200줄 초과 방지를 위해 분리했다.
// forms.dart 배럴에는 올리지 않는다(BaraedaCodeInput 내부 구현이라
// 바깥 앱이 직접 쓸 일이 없다).

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// `BaraedaCodeInput` 한 칸을 그리는 장식용 박스. 실제 입력은 받지 않는다
/// (진짜 입력은 투명 `TextField`가 받는다).
class BaraedaCodeInputBox extends StatelessWidget {
  const BaraedaCodeInputBox({
    required this.char,
    required this.active,
    required this.hasError,
    super.key,
  });

  final String char;
  final bool active;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final Color borderColor;
    if (hasError) {
      borderColor = colors.statusMissed;
    } else if (active) {
      borderColor = colors.accentPrimary;
    } else {
      borderColor = colors.borderControl;
    }

    return Container(
      width: 44,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        border: Border.all(
          color: borderColor,
          width: active
              ? BaraedaBorderWidth.strong
              : BaraedaBorderWidth.hairline,
        ),
        borderRadius: BorderRadius.circular(BaraedaRadius.md),
      ),
      child: Text(
        char,
        style: BaraedaTypography.numeric.copyWith(color: colors.textPrimary),
      ),
    );
  }
}

/// 입력값을 항상 대문자로 강제한다(원본 "auto-uppercase").
class BaraedaUpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
