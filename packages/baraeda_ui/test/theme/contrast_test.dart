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
    for (final MapEntry(key: name, value: pair) in pairs.entries) {
      test('$name 은 4.5:1 이상', () {
        expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(minText));
      });
    }
  });

  group('다크 테마 글자 명도 대비(회귀 방지)', () {
    const c = BaraedaColors.dark;
    final pairs = <String, (Color, Color)>{
      '보조 글자 on 카드': (c.textTertiary, c.surfaceCard),
      '이동 중 글자 on 카드': (c.statusMoving, c.surfaceCard),
      '미승차 글자 on 카드': (c.statusMissed, c.surfaceCard),
    };
    for (final MapEntry(key: name, value: pair) in pairs.entries) {
      test('$name 은 4.5:1 이상', () {
        expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(minText));
      });
    }
  });

  // 비텍스트 UI 경계 3:1 (WCAG 1.4.11) — 조작 요소 전용 토큰 `borderControl` (F07-09, Ruling 403).
  // 경계선은 자기 안쪽 면(입력칸 배경 = 카드)과 바깥 면(페이지 바탕·카드) 양쪽에서 구분돼야 한다.
  group('조작 요소 경계 명도 대비 3:1', () {
    const minUi = 3.0;
    final themes = <String, BaraedaColors>{
      '라이트': BaraedaColors.light,
      '다크': BaraedaColors.dark,
    };
    for (final MapEntry(key: name, value: c) in themes.entries) {
      final surfaces = <String, Color>{
        '카드': c.surfaceCard,
        '페이지 바탕': c.bgBase,
        '떠 있는 면': c.surfaceRaised,
      };
      for (final MapEntry(key: surfaceName, value: surface)
          in surfaces.entries) {
        test('$name borderControl on $surfaceName 은 3:1 이상', () {
          expect(
            _contrast(c.borderControl, surface),
            greaterThanOrEqualTo(minUi),
          );
        });
      }
    }

    test('borderControl 은 불투명이다 — computeLuminance 는 알파를 무시하므로', () {
      for (final c in themes.values) {
        expect(c.borderControl.a, 1.0);
      }
    });

    test('카드 외곽선 borderDefault 는 그대로 둔다(전 화면 테두리가 진해지지 않게)', () {
      expect(BaraedaColors.light.borderDefault, BaraedaPalette.stone300);
      expect(BaraedaColors.dark.borderDefault, const Color(0x3DEDF2EF));
    });
  });
}
