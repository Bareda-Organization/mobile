// 원본 `design-system/components/forms/SearchField.jsx` 대응.
// 원본은 `<form onSubmit>`으로 제출을 잡지만, Flutter는 폼 제출 개념이 없어
// `TextField.onSubmitted`(키보드의 "검색"/엔터)로 옮긴다.

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:baraeda_ui/widgets/core/icon.dart';
import 'package:flutter/material.dart';

/// 검색 입력 — 왼쪽 돋보기 아이콘 고정, [onSubmit]은 엔터/키보드 검색 키.
class BaraedaSearchField extends StatelessWidget {
  const BaraedaSearchField({
    super.key,
    this.value,
    this.onChanged,
    this.onSubmit,
    this.placeholder = '검색',
    this.controller,
  });

  final String? value;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmit;
  final String placeholder;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      textField: true,
      label: placeholder,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmit,
        textInputAction: TextInputAction.search,
        style: BaraedaTypography.body.copyWith(color: colors.textPrimary),
        decoration: InputDecoration(
          filled: true,
          fillColor: colors.bgSubtle,
          hintText: placeholder,
          hintStyle: BaraedaTypography.body.copyWith(
            color: colors.textTertiary,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: BaraedaIcon('search', color: colors.textTertiary, size: 18),
          ),
          prefixIconConstraints: const BoxConstraints(),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BaraedaRadius.pill),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BaraedaRadius.pill),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BaraedaRadius.pill),
            borderSide: BorderSide(
              color: colors.accentPrimary,
              width: BaraedaBorderWidth.strong,
            ),
          ),
        ),
      ),
    );
  }
}
