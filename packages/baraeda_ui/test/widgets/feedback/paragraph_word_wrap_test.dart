import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/line_breaks.dart';

/// 여러 줄로 바뀔 수 있는 안내·본문 문단은 낱말 한가운데서 줄이 바뀌면 안 된다(R46-POLISH Ruling 594).
/// 문단마다 위젯을 375pt 폭에서 글자 1.0·1.3배로 그려, 그 문장을 그린 글자 덩어리의 줄 끝을 본다.
const _sentence = '승하차지·명단이 변경됐습니다 — 확인 후 계속 진행하세요. 학부모에게 바로 알려 드립니다';

final _cases = <String, Widget Function()>{
  '배너 본문': () => const AlertBanner(tone: AlertTone.info, body: _sentence),
  '배너 제목': () => const AlertBanner(tone: AlertTone.info, title: _sentence),
  '빈 상태 본문': () => const EmptyState(title: '비었습니다', body: _sentence),
  '대화상자 본문': () => const SizedBox(
    height: 800,
    child: Stack(
      children: [BaraedaDialog(title: '확인', body: _sentence)],
    ),
  ),
  '알림 본문': () => const NotificationTile(
    icon: 'map-pin',
    status: BaraedaStatus.moving,
    kindLabel: '미승차',
    title: '미승차 안내',
    body: _sentence,
    time: '8:37',
    timeSpoken: '오전 8시 37분',
  ),
  '입력칸 안내': () => const BaraedaInput(label: '메모', hint: _sentence),
  '입력칸 오류': () => const BaraedaInput(label: '메모', error: _sentence),
  '여러 줄 입력칸 안내': () => const BaraedaTextarea(label: '메모', hint: _sentence),
  '스위치 보조 문구': () =>
      const BaraedaSwitch(checked: true, label: '알림', sublabel: _sentence),
};

void main() {
  for (final scale in const [1.0, 1.3]) {
    for (final entry in _cases.entries) {
      testWidgets('${entry.key} — 낱말 중간에서 줄이 바뀌지 않는다 (375pt · 글자 $scale배)', (
        tester,
      ) async {
        tester.view
          ..physicalSize = const Size(375, 800)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: BaraedaTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(body: SingleChildScrollView(child: entry.value())),
          ),
        );

        final paragraph = tester.renderObject<RenderParagraph>(
          find.byWidgetPredicate(
            (widget) =>
                widget is RichText &&
                widget.text
                        .toPlainText(includeSemanticsLabels: false)
                        .replaceAll('\u2060', '') ==
                    _sentence,
          ),
        );
        expect(
          layoutLike(paragraph).computeLineMetrics().length,
          greaterThan(1),
          reason: '줄이 바뀌어야 이 시험이 무언가를 검사한다',
        );
        expect(midWordLineBreaks(paragraph), isEmpty);
      });
    }
  }
}
