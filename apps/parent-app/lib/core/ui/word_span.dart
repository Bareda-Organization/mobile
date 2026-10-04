import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/painting.dart';

/// 낱말 단위로만 줄을 바꾸되(`WordWrapText` 와 같은 규칙) 굵게 칠할 조각을 섞을 수 있는 글자 조각.
/// 낭독기와 시험이 원문을 읽도록 `semanticsLabel` 을 같이 둔다.
TextSpan wordSpan(String text, {TextStyle? style}) => TextSpan(
  text: WordWrapText.keepWords(text),
  semanticsLabel: text,
  style: style,
);
