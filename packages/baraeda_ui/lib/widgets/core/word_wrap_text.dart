// 낱말 단위로만 줄을 바꾸는 문단 글자 — 여러 줄 안내·본문용.

import 'package:flutter/widgets.dart';

/// 낱말 안 글자 사이에 끼워 줄바꿈 후보를 없애는 WORD JOINER(U+2060).
const _wordJoiner = '\u2060';

/// 공백으로 나뉜 낱말 안에서는 줄을 바꾸지 않는 [Text].
///
/// Flutter 기본 줄바꿈은 한글을 음절마다 끊을 수 있어 `연락처 / 는` 처럼 낱말 한가운데서 줄이 바뀐다
/// (R46-SCREEN 화면 확인 7곳, R46-POLISH Ruling 594). CSS `word-break: keep-all`
/// 과 같은 효과를 내려고
/// 낱말 안 글자 사이에 [_wordJoiner] 를 끼운다 — 줄은 공백에서만 바뀌고, 낱말 하나가 한 줄보다 길면
/// 그때만 글자 단위로 끊는다.
///
/// 낭독과 `find.text` 는 원문을 쓴다(`semanticsLabel`). **한 줄 요소(버튼·라벨·칩)에는 쓰지 않는다** —
/// 가장 긴 낱말이 최소 폭이 되어 좁은 칸에서 오히려 넘칠 수 있다.
class WordWrapText extends StatelessWidget {
  const WordWrapText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(text: keepWords(data), semanticsLabel: data),
    style: style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
  );

  /// [text] 의 낱말(공백이 아닌 연속) 안 글자 사이마다 [_wordJoiner] 를 끼운 문자열.
  /// 글자는 자소·이모지 묶음 단위로 센다 — 묶음 한가운데에 끼우면 글자가 깨진다.
  static String keepWords(String text) => text.splitMapJoin(
    RegExp(r'\S+'),
    onMatch: (match) => Characters(match[0]!).join(_wordJoiner),
  );
}
