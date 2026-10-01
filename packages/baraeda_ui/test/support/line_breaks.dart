import 'package:flutter/rendering.dart';

/// [paragraph] 와 같은 글자·폭·줄 수 설정으로 다시 배치한 [TextPainter] —
/// `RenderParagraph` 는 줄 경계를 직접 알려 주지 않아, 같은 엔진 배치를 한 번 더 해서
/// 줄 정보를 읽는다.
TextPainter layoutLike(RenderParagraph paragraph) => TextPainter(
  text: paragraph.text,
  textAlign: paragraph.textAlign,
  textDirection: paragraph.textDirection,
  textScaler: paragraph.textScaler,
  maxLines: paragraph.maxLines,
  ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '…' : null,
  locale: paragraph.locale,
  strutStyle: paragraph.strutStyle,
  textWidthBasis: paragraph.textWidthBasis,
)..layout(maxWidth: paragraph.constraints.maxWidth);

/// [paragraph] 에서 줄이 낱말 한가운데서 바뀐 자리들 — `앞4글자|뒤4글자` 로 돌려준다. 비어 있으면 모든 줄 끝이
/// 공백(낱말 경계)이다. 그려진 글자(낱말 이음 문자 포함) 기준이며, 마지막 줄은 보지 않는다 —
/// 말줄임(…)으로 줄 수를 막은 문단은 마지막 줄이 낱말 한가운데서 잘리는 것이 정상이다.
List<String> midWordLineBreaks(RenderParagraph paragraph) {
  final text = paragraph.text.toPlainText(includeSemanticsLabels: false);
  final painter = layoutLike(paragraph);
  final wrappedLines = painter.computeLineMetrics().length - 1;
  final breaks = <String>[];
  var offset = 0;
  for (var line = 0; line < wrappedLines; line++) {
    final end = painter.getLineBoundary(TextPosition(offset: offset)).end;
    if (end <= offset || end >= text.length) break;
    final atWordBoundary =
        text[end - 1].trim().isEmpty || text[end].trim().isEmpty;
    if (!atWordBoundary) {
      final from = end < 4 ? 0 : end - 4;
      final to = end + 4 > text.length ? text.length : end + 4;
      breaks.add('${text.substring(from, end)}|${text.substring(end, to)}');
    }
    offset = end;
  }
  return breaks;
}
