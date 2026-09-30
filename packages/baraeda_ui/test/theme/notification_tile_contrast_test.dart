// R44 — 알림 행의 명도 대비. 글자 4.5:1 · 아이콘·점·막대 3:1 (WCAG 1.4.3 · 1.4.11).
// 다크 테마의 옅은 색은 알파가 있어 바탕에 겹친 값으로 계산한다.
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
  const minGraphic = 3.0;

  final themes = <String, BaraedaColors>{
    '라이트': BaraedaColors.light,
    '다크': BaraedaColors.dark,
  };

  for (final MapEntry(key: themeName, value: c) in themes.entries) {
    // 읽은 행은 페이지 바탕 그대로, 안 읽은 행은 그 위에 옅은 강조색이 겹친다.
    final readBg = c.bgBase;
    final unreadBg = Color.alphaBlend(c.accentPrimarySoft, c.bgBase);
    final tones = <String, (Color, Color)>{
      '승차·하차(초록)': (c.statusBoarded, c.statusBoardedSoft),
      '지연·노선 변경(앰버)': (c.statusMoving, c.statusMovingSoft),
      '미승차·비상(레드)': (c.statusMissed, c.statusMissedSoft),
      '안내(스톤)': (c.statusIdle, c.statusIdleSoft),
    };

    group('$themeName 알림 행 글자 4.5:1', () {
      final pairs = <String, (Color, Color)>{
        '제목 on 읽은 행': (c.textPrimary, readBg),
        '제목 on 안 읽은 행': (c.textPrimary, unreadBg),
        '본문·시각 on 읽은 행': (c.textSecondary, readBg),
        '본문·시각 on 안 읽은 행': (c.textSecondary, unreadBg),
        for (final MapEntry(key: name, value: tone) in tones.entries) ...{
          '중요 글자 $name on 읽은 행': (tone.$1, readBg),
          '중요 글자 $name on 안 읽은 행': (tone.$1, unreadBg),
        },
      };
      for (final MapEntry(key: name, value: pair) in pairs.entries) {
        test(name, () {
          final ratio = _contrast(pair.$1, pair.$2);
          // 보고서에 계산값을 옮기려고 출력한다.
          // ignore: avoid_print
          print('CONTRAST $themeName | $name | ${ratio.toStringAsFixed(2)}');
          expect(ratio, greaterThanOrEqualTo(minText));
        });
      }
    });

    group('$themeName 알림 행 아이콘·점·막대 3:1', () {
      final pairs = <String, (Color, Color)>{
        for (final MapEntry(key: name, value: tone) in tones.entries) ...{
          // 읽은 행: 옅은 원(바탕에 겹친 값) 위 상태 색 글리프.
          '읽은 아이콘 $name': (tone.$1, Color.alphaBlend(tone.$2, readBg)),
          // 안 읽은 행: 꽉 찬 원 위 반전 글리프.
          '안 읽은 아이콘 $name': (c.textInverse, tone.$1),
          '중요 막대 $name on 읽은 행': (tone.$1, readBg),
          '중요 막대 $name on 안 읽은 행': (tone.$1, unreadBg),
        },
        '안 읽음 점 on 안 읽은 행': (c.accentPrimary, unreadBg),
      };
      for (final MapEntry(key: name, value: pair) in pairs.entries) {
        test(name, () {
          final ratio = _contrast(pair.$1, pair.$2);
          // 보고서에 계산값을 옮기려고 출력한다.
          // ignore: avoid_print
          print('CONTRAST $themeName | $name | ${ratio.toStringAsFixed(2)}');
          expect(ratio, greaterThanOrEqualTo(minGraphic));
        });
      }
    });
  }
}
