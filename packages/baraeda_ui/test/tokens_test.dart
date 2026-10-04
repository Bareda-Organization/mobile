// 토큰 대조 시험 — `frontend/design-system/tokens/*.css` 의 값이 Dart 상수로
// 정확히 옮겨졌는지 고정한다. 이 시험은 이식 실수(오타·자릿수)를 잡는 것이
// 목적이라, CSS 원본의 대표값을 그대로 적어 비교한다.
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('원시 팔레트 — colors.css', () {
    test('바래다 그린(--green-600)은 #1F5C4D', () {
      expect(BaraedaPalette.green600, const Color(0xFF1F5C4D));
    });

    test('미스트 그린(--green-100)은 #E8F0EC', () {
      expect(BaraedaPalette.green100, const Color(0xFFE8F0EC));
    });

    test('버스 앰버(--amber-500)는 #F5A623', () {
      expect(BaraedaPalette.amber500, const Color(0xFFF5A623));
    });

    test('브랜드 별칭은 원시 팔레트를 그대로 가리킨다', () {
      expect(BaraedaPalette.baraedaGreen, BaraedaPalette.green600);
      expect(BaraedaPalette.mistGreen, BaraedaPalette.green100);
      expect(BaraedaPalette.busAmber, BaraedaPalette.amber500);
    });
  });

  group('의미 색 — semantic.css [data-theme="dark"]', () {
    test('다크 기본 바탕(--bg-base)은 #0F1412', () {
      expect(BaraedaColors.dark.bgBase, const Color(0xFF0F1412));
    });
  });

  group('상태 색 매핑 — 세 제품 공통, CONVENTIONS_FLUTTER.md §3', () {
    test('라이트: boarded 그린 · moving 앰버잉크 · missed 레드잉크 · idle 스톤', () {
      expect(BaraedaColors.light.statusBoarded, BaraedaPalette.green600);
      expect(BaraedaColors.light.statusMoving, BaraedaPalette.amberInk);
      expect(BaraedaColors.light.statusMissed, BaraedaPalette.redInk);
      expect(BaraedaColors.light.statusIdle, BaraedaPalette.stone600);
    });

    test('다크: boarded/moving 는 액션이 앰버로, missed 는 밝은 레드로 바뀐다', () {
      expect(BaraedaColors.dark.statusBoarded, const Color(0xFF5FD0AC));
      expect(BaraedaColors.dark.statusMoving, BaraedaPalette.amber500);
      expect(BaraedaColors.dark.statusMissed, BaraedaPalette.red300);
      expect(BaraedaColors.dark.statusIdle, const Color(0xFF93A09B));
    });
  });

  group('타이포그래피 — typography.css', () {
    test('본문은 16px / line-height 1.5 / Noto Sans KR', () {
      expect(BaraedaTypography.body.fontSize, 16);
      expect(BaraedaTypography.body.height, 1.5);
      expect(BaraedaTypography.body.fontFamily, 'Noto Sans KR');
    });

    test('글자 크기는 시안 8단계(13·14·16·20·24·30·40·52)뿐이다', () {
      expect(BaraedaFontSize.scale, [13, 14, 16, 20, 24, 30, 40, 52]);
      final styles = <String, TextStyle>{
        'display': BaraedaTypography.display,
        'h1': BaraedaTypography.h1,
        'h2': BaraedaTypography.h2,
        'h3': BaraedaTypography.h3,
        'title': BaraedaTypography.title,
        'bodyLg': BaraedaTypography.bodyLg,
        'body': BaraedaTypography.body,
        'bodySm': BaraedaTypography.bodySm,
        'caption': BaraedaTypography.caption,
        'micro': BaraedaTypography.micro,
        'label': BaraedaTypography.label,
        'labelSm': BaraedaTypography.labelSm,
        'numeric': BaraedaTypography.numeric,
      };
      for (final MapEntry(key: name, value: style) in styles.entries) {
        expect(
          BaraedaFontSize.scale,
          contains(style.fontSize),
          reason: '$name 의 크기 ${style.fontSize} 가 8단계 밖이다',
        );
      }
    });

    test('시트·대화상자 제목은 나눔명조 700 / 20px', () {
      expect(BaraedaTypography.title.fontFamily, 'Nanum Myeongjo');
      expect(BaraedaTypography.title.fontWeight, FontWeight.w700);
      expect(BaraedaTypography.title.fontSize, 20);
    });

    test('h1 은 나눔명조 700 / 40px', () {
      expect(BaraedaTypography.h1.fontFamily, 'Nanum Myeongjo');
      expect(BaraedaTypography.h1.fontWeight, FontWeight.w700);
      expect(BaraedaTypography.h1.fontSize, 40);
    });
  });

  group('시안 색 — mkit `:root`', () {
    test('꺼진 단추 글자는 기존 보조 글자색 #5C665F 다(새 색 #636D69 금지, Ruling 829)', () {
      expect(BaraedaColors.light.disabledText, const Color(0xFF5C665F));
      expect(
        BaraedaColors.light.disabledText,
        BaraedaColors.light.textSecondary,
      );
      expect(BaraedaColors.light.disabledText, isNot(const Color(0xFF636D69)));
    });

    test('위험 단추 면 #C93F2C · 위험 글자 #A8301F · 이동 중 글자 #8A560C', () {
      expect(BaraedaColors.light.dangerSolid, const Color(0xFFC93F2C));
      expect(BaraedaColors.light.statusMissed, const Color(0xFFA8301F));
      expect(BaraedaColors.light.statusMoving, const Color(0xFF8A560C));
    });

    test('칩 모양 색 5종(라이트): 종료 #6B7672 · 이동 #C77E12 · 확정 #1F5C4D · 대기 #7BBAA6 · 위험 #C93F2C', () {
      const c = BaraedaColors.light;
      expect(c.shapeIdle, const Color(0xFF6B7672));
      expect(c.shapeMoving, const Color(0xFFC77E12));
      expect(c.shapeBoarded, const Color(0xFF1F5C4D));
      expect(c.shapeWait, const Color(0xFF7BBAA6));
      expect(c.dangerSolid, const Color(0xFFC93F2C));
    });
  });

  group('여백 — space.css', () {
    test('4px 배수 스케일', () {
      expect(BaraedaSpacing.space4, 16);
      expect(BaraedaSpacing.space6, 24);
    });

    test('최소 터치 영역은 48px', () {
      expect(BaraedaSpacing.tapMin, 48);
    });
  });

  group('모양 — shape.css', () {
    test('카드 반경은 16px', () {
      expect(BaraedaRadius.card, 16);
    });
  });

  group('모션 — 시안 움직임 약속', () {
    test('누름 120ms · 일반 180ms · 시트 240ms · 대화상자 200ms · 토스트 220ms', () {
      expect(BaraedaDuration.press, const Duration(milliseconds: 120));
      expect(BaraedaDuration.ui, const Duration(milliseconds: 180));
      expect(BaraedaDuration.sheet, const Duration(milliseconds: 240));
      expect(BaraedaDuration.dialog, const Duration(milliseconds: 200));
      expect(BaraedaDuration.toast, const Duration(milliseconds: 220));
    });

    test('ease-out cubic-bezier(.23,1,.32,1) · 서랍 곡선(.32,.72,0,1)', () {
      expect(BaraedaCurve.easeOut, const Cubic(0.23, 1, 0.32, 1));
      expect(BaraedaCurve.drawer, const Cubic(0.32, 0.72, 0, 1));
    });
  });

  group('모션 — motion.css', () {
    test('기본 지속시간은 240ms', () {
      expect(BaraedaDuration.base, const Duration(milliseconds: 240));
    });

    test('표준 이징은 cubic-bezier(.2,0,.2,1)', () {
      expect(BaraedaCurve.standard, const Cubic(0.2, 0, 0.2, 1));
    });
  });
}
