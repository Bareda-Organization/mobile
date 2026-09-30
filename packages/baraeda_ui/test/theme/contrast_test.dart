// 명도 대비 시험 — WCAG 2.x 본문 글자 4.5:1 (F07-09). 글자색과 그 글자가 올라가는 면을
// 짝지어 고정한다. 계산은 Flutter 의 `Color.computeLuminance`(상대 휘도)를 쓴다.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  const minText = 4.5;

  group('라이트 테마 글자 명도 대비', () {
    const c = BaraedaColors.light;
    final pairs = <String, (Color, Color)>{
      '보조 글자 on 카드': (c.textTertiary, c.surfaceCard),
      '보조 글자 on 페이지 바탕': (c.textTertiary, c.bgBase),
      '보조 글자 on 옅은 면(검색창·부제)': (c.textTertiary, c.bgSubtle),
      '이동 중 글자 on 카드(현재 정류장 시각)': (c.statusMoving, c.surfaceCard),
      '이동 중 글자 on 이동 중 알약 배경': (c.statusMoving, c.statusMovingSoft),
      '미승차 글자 on 미승차 알약 배경': (c.statusMissed, c.statusMissedSoft),
      '대기 글자 on 대기 알약 배경': (c.statusIdle, c.statusIdleSoft),
      '탑승 글자 on 탑승 알약 배경': (c.statusBoarded, c.statusBoardedSoft),
      '2차 글자 on 카드': (c.textSecondary, c.surfaceCard),
    };
    pairs.forEach((name, pair) {
      test('$name 은 4.5:1 이상', () {
        expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(minText));
      });
    });
  });

  group('다크 테마 글자 명도 대비(회귀 방지)', () {
    const c = BaraedaColors.dark;
    final pairs = <String, (Color, Color)>{
      '보조 글자 on 카드': (c.textTertiary, c.surfaceCard),
      '이동 중 글자 on 카드': (c.statusMoving, c.surfaceCard),
      '미승차 글자 on 카드': (c.statusMissed, c.surfaceCard),
    };
    pairs.forEach((name, pair) {
      test('$name 은 4.5:1 이상', () {
        expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(minText));
      });
    });
  });
}
