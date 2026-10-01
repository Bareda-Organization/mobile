import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/line_breaks.dart';

const _sentence = '승하차지·명단이 변경됐습니다 — 확인 후 계속 진행하세요 학부모에게 바로 알려 드립니다';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 320, child: child),
    ),
  ),
);

void main() {
  testWidgets('줄은 낱말 경계(공백)에서만 바뀐다', (tester) async {
    await tester.pumpWidget(_host(const WordWrapText(_sentence)));

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText),
    );
    expect(
      layoutLike(paragraph).computeLineMetrics().length,
      greaterThan(1),
      reason: '줄이 바뀌어야 이 시험이 무언가를 검사한다',
    );
    expect(midWordLineBreaks(paragraph), isEmpty);
  });

  testWidgets('같은 문장을 기본 Text 로 그리면 낱말 한가운데서 끊긴다 — 위 검사가 결함을 잡는지 확인', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const Text(_sentence)));

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText),
    );
    expect(midWordLineBreaks(paragraph), isNotEmpty);
  });

  testWidgets('낭독과 글자 찾기는 원문을 쓴다', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const WordWrapText(_sentence)));

    expect(find.text(_sentence), findsOneWidget);
    expect(tester.getSemantics(find.byType(RichText)).label, _sentence);
    handle.dispose();
  });

  testWidgets('줄 수 제한과 말줄임이 그대로 동작한다', (tester) async {
    await tester.pumpWidget(
      _host(
        const WordWrapText(
          _sentence,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText),
    );
    expect(layoutLike(paragraph).computeLineMetrics().length, 2);
    expect(layoutLike(paragraph).didExceedMaxLines, isTrue);
  });

  testWidgets('한 줄보다 긴 낱말은 넘치지 않고 글자 단위로 끊긴다', (tester) async {
    await tester.pumpWidget(
      _host(const WordWrapText('가나다라마바사아자차카타파하가나다라마바사아자차카타파하가나다라마바사')),
    );

    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(RichText));
    expect(size.width, lessThanOrEqualTo(320));
  });
}
