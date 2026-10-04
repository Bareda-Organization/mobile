// 원본 `design-system/components/forms/SegmentedControl.jsx` 대응 + 시안 `.m-seg`.
//
// Flutter 내장 위젯 중 이 알약형 트랙 선택자와 정확히 맞는 것이 없다
// (`SegmentedButton`은 Material 3 스타일 사각 세그먼트라 radius·배경이
// 브랜드와 다르고, 겹쳐 쓰면 오버라이드가 커스텀 구현보다 더 늘어난다).
// 그래서 `role=tablist/tab` 시맨틱만 원본과 맞추고 나머지는 완전히
// 새로 그린다 — `Row` 안에 알약 버튼을 늘어놓고 선택된 항목만 배경을 채운다.
// 시안: 선택된 칸 = 초록 면 + 흰 글자(웹 `.pill-tab.on` 과 같다).

import 'package:baraeda_ui/theme/baraeda_colors.dart';
import 'package:baraeda_ui/tokens/motion.dart';
import 'package:baraeda_ui/tokens/shape.dart';
import 'package:baraeda_ui/tokens/spacing.dart';
import 'package:baraeda_ui/tokens/typography.dart';
import 'package:flutter/material.dart';

/// [BaraedaSegmentedControl]의 선택지 하나.
class BaraedaSegmentedOption {
  const new(this.value, {String? label}) : label = label ?? value;

  final String value;
  final String label;
}

/// 탭처럼 동작하는 세그먼트 선택자(예: "전체 · 승차 · 하차"). 칸 높이는 44 이상이다.
class BaraedaSegmentedControl extends StatelessWidget {
  const new({
    required this.options,
    required this.value,
    super.key,
    this.onChanged,
    this.block = false,
    this.wrapByWord = false,
  });

  final List<BaraedaSegmentedOption> options;
  final String value;
  final ValueChanged<String>? onChanged;

  /// 가로 100%로 균등 분할.
  final bool block;

  /// `true` 면 라벨을 낱말 단위로 줄바꿈한다 — 칸이 좁을 때 "차량 고/장" 처럼 낱말 중간에서 끊기지 않고
  /// "차량 / 고장" 두 줄이 된다. 칸이 4개 이상인 좁은 화면에서 켠다(R46). 기본값은 예전 그대로다.
  final bool wrapByWord;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(BaraedaSpacing.space1),
        decoration: BoxDecoration(
          color: colors.statusIdleSoft,
          borderRadius: BorderRadius.circular(BaraedaRadius.pill),
        ),
        child: Row(
          mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(width: BaraedaSpacing.space1),
              _SegmentedButton(
                option: options[i],
                selected: options[i].value == value,
                expand: block,
                wrapByWord: wrapByWord,
                colors: colors,
                onSelected: onChanged == null
                    ? null
                    : () => onChanged!(options[i].value),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SegmentedButton extends StatelessWidget {
  const new({
    required this.option,
    required this.selected,
    required this.expand,
    required this.wrapByWord,
    required this.colors,
    required this.onSelected,
  });

  final BaraedaSegmentedOption option;
  final bool selected;
  final bool expand;
  final bool wrapByWord;
  final BaraedaColors colors;
  final VoidCallback? onSelected;

  /// 낱말마다 따로 그려 `Wrap` 이 낱말 경계에서만 줄을 바꾸게 한다.
  Widget _wordWrapped(TextStyle style) => Wrap(
    alignment: WrapAlignment.center,
    runAlignment: WrapAlignment.center,
    spacing: 4,
    children: [
      for (final word in option.label.split(' '))
        Text(word, textAlign: TextAlign.center, style: style),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final labelStyle = BaraedaTypography.body.copyWith(
      fontWeight: BaraedaFontWeight.medium,
      height: 1,
      color: selected ? colors.textInverse : colors.textSecondary,
    );
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
          duration: BaraedaDuration.ui,
          curve: BaraedaCurve.easeOut,
          alignment: Alignment.center,
          constraints: const BoxConstraints(minHeight: BaraedaSpacing.tap),
          // 낱말 단위 줄바꿈일 때는 좌우 여백을 줄여 낱말이 들어갈 폭을 늘린다.
          padding: EdgeInsets.symmetric(
            horizontal: wrapByWord ? 6 : 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.accentPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(BaraedaRadius.pill),
          ),
          child: wrapByWord
              ? _wordWrapped(labelStyle)
              : Text(
                  option.label,
                  textAlign: TextAlign.center,
                  style: labelStyle,
                ),
        ),
      ),
    );

    return expand ? Expanded(child: button) : button;
  }
}
